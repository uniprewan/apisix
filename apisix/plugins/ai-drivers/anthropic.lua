--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

local core = require("apisix.core")
local http = require("resty.http")
local url = require("resty.url")
local openai_base = require("apisix.plugins.ai-drivers.openai-base")

local _M = {}

-- Native Protocol Constants
local NATIVE_HOST = "api.anthropic.com"
local NATIVE_PATH = "/v1/messages"
local NATIVE_PORT = 443
local ANTHROPIC_VERSION = "2023-06-01"

-- Legacy (OpenAI-Compatible) Protocol Constants
local LEGACY_HOST = "api.anthropic.com"
local LEGACY_PATH = "/v1/chat/completions"

-- HTTP Status Codes
local HTTP_INTERNAL_SERVER_ERROR = 500
local HTTP_BAD_REQUEST = 400

-- Content Type
local CONTENT_TYPE_JSON = "application/json"

-- ######################################################
-- ## Native Protocol Implementation
-- ######################################################

-- Extract system message from messages array for native protocol
local function extract_system_message(messages)
    local system_content = nil
    local user_messages = {}
    if not messages or type(messages) ~= "table" then
        return system_content, user_messages
    end
    for _, msg in ipairs(messages) do
        if type(msg) == "table" then
            if msg.role == "system" then
                system_content = msg.content
            else
                table.insert(user_messages, msg)
            end
        end
    end
    return system_content, user_messages
end

-- Convert OpenAI format request to Anthropic native format
local function convert_request_to_anthropic(request_body)
    local request_table, err = core.json.decode(request_body)
    if err then
        return nil, "Failed to decode request body: " .. err
    end

    local system_content, user_messages = extract_system_message(request_table.messages)

    local anthropic_request = {
        model = request_table.model,
        messages = user_messages,
        max_tokens = request_table.max_tokens or 1024,
    }

    if system_content then
        anthropic_request.system = system_content
    end

    if request_table.temperature then
        anthropic_request.temperature = request_table.temperature
    end
    if request_table.top_p then
        anthropic_request.top_p = request_table.top_p
    end
    if request_table.stream then
        anthropic_request.stream = request_table.stream
    end

    local encoded_body, err = core.json.encode(anthropic_request)
    if err then
        return nil, "Failed to encode Anthropic request: " .. err
    end
    return encoded_body, nil
end

-- Convert Anthropic native format response to OpenAI format
local function convert_response_to_openai(response_body)
    local response_table, err = core.json.decode(response_body)
    if err then
        return nil, "Failed to decode response body: " .. err
    end

    local content_text = ""
    if type(response_table.content) == "table" then
        for _, content_item in ipairs(response_table.content) do
            if type(content_item) == "table" and content_item.type == "text" then
                content_text = content_text .. (content_item.text or "")
            end
        end
    end

    local finish_reason = "stop"
    if response_table.stop_reason == "max_tokens" then
        finish_reason = "length"
    end

    local openai_response = {
        id = response_table.id or "",
        object = "chat.completion",
        created = math.floor(core.utils.now()),
        model = response_table.model or "",
        choices = {
            {
                index = 0,
                message = {
                    role = "assistant",
                    content = content_text,
                },
                finish_reason = finish_reason,
            }
        },
        usage = {
            prompt_tokens = (response_table.usage and response_table.usage.input_tokens) or 0,
            completion_tokens = (response_table.usage and response_table.usage.output_tokens) or 0,
            total_tokens = ((response_table.usage and response_table.usage.input_tokens) or 0) +
                          ((response_table.usage and response_table.usage.output_tokens) or 0),
        }
    }

    local encoded_response, err = core.json.encode(openai_response)
    if err then
        return nil, "Failed to encode OpenAI response: " .. err
    end
    return encoded_response, nil
end

-- Handles the request using the native protocol
function _M.request_native(self, ctx, conf)
    local httpc, err = http.new()
    if not httpc then
        core.log.error("failed to create http client: ", err)
        return HTTP_INTERNAL_SERVER_ERROR
    end

    httpc:set_timeout(conf.timeout or 30000)

    local ok, err = httpc:connect({
        scheme = "https",
        host = NATIVE_HOST,
        port = NATIVE_PORT,
        ssl_verify = conf.ssl_verify ~= false,
        ssl_server_name = NATIVE_HOST,
    })
    if not ok then
        core.log.warn("failed to connect to Anthropic API: ", err)
        return HTTP_INTERNAL_SERVER_ERROR
    end

    local original_body = core.request.get_body()
    local anthropic_body, err = convert_request_to_anthropic(original_body)
    if err then
        core.log.error("failed to convert request: ", err)
        return HTTP_BAD_REQUEST
    end

    local headers = {
        ["Content-Type"] = CONTENT_TYPE_JSON,
        ["x-api-key"] = conf.auth and conf.auth.api_key or "",
        ["anthropic-version"] = ANTHROPIC_VERSION
    }

    local res, err = httpc:request({
        method = "POST",
        path = NATIVE_PATH,
        headers = headers,
        body = anthropic_body,
    })

    if not res then
        core.log.warn("failed to send request to Anthropic API: ", err)
        return HTTP_INTERNAL_SERVER_ERROR
    end

    if res.status >= 400 then
        return res.status, res:read_body()
    end

    local response_body, err = res:read_body()
    if not response_body then
        core.log.warn("failed to read response body: ", err)
        return HTTP_INTERNAL_SERVER_ERROR
    end

    local openai_response, err = convert_response_to_openai(response_body)
    if err then
        core.log.warn("failed to convert response: ", err)
        openai_response = response_body
    end

    ngx.status = res.status
    for key, value in pairs(res.headers) do
        ngx.header[key] = value
    end

    if conf.keepalive then
        httpc:set_keepalive(conf.keepalive_timeout or 60000, conf.keepalive_pool or 10)
    end

    return res.status, openai_response
end

-- ######################################################
-- ## Legacy (OpenAI-Compatible) Protocol Implementation
-- ######################################################

-- Handles the request using the legacy protocol by delegating to openai-base
function _M.request_legacy(self, ctx, conf, request_table, extra_opts)
    core.log.info("Using Anthropic legacy (OpenAI-compatible) protocol.")
    local legacy_driver = openai_base.new({
        host = LEGACY_HOST,
        path = LEGACY_PATH,
    })
    return legacy_driver:request(ctx, conf, request_table, extra_opts)
end

-- ######################################################
-- ## Main Driver Logic
-- ######################################################

function _M.new(opts)
    return setmetatable({}, { __index = _M })
end

function _M.validate_request(ctx)
    local content_type = core.request.get_header("Content-Type")
    if not content_type or not core.string.has_prefix(content_type, CONTENT_TYPE_JSON) then
        return nil, "Unsupported content type: " .. tostring(content_type) .. ", only application/json is supported"
    end

    local request_body = core.request.get_body()
    if not request_body or request_body == "" then
        return nil, "Empty request body"
    end

    local request_table, err = core.json.decode(request_body)
    if err then
        return nil, "Invalid JSON in request body: " .. err
    end

    if not request_table.messages or type(request_table.messages) ~= "table" then
        return nil, "Missing or invalid 'messages' field"
    end

    if not request_table.model or type(request_table.model) ~= "string" then
        return nil, "Missing or invalid 'model' field"
    end

    return request_table, nil
end

-- Main request function that routes to native or legacy implementation
function _M.request(self, ctx, conf, request_table, extra_opts)
    if conf.model.options and conf.model.options.native_protocol == true then
        return self:request_native(ctx, conf)
    else
        return self:request_legacy(ctx, conf, request_table, extra_opts)
    end
end

return _M
