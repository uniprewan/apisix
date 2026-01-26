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
local sse = require("apisix.plugins.ai-drivers.sse")
local plugin = require("apisix.plugin")

local _M = {
    host = "api.anthropic.com",
    port = 443,
    path = "/v1/messages",
}

-- Validate the request body against the OpenAI-compatible schema.
-- The client-facing request is always expected to be in OpenAI format.
function _M.validate_request(ctx)
    local drivers_schema = require("apisix.plugins.ai-drivers.schema")
    return core.schema.validate(drivers_schema.chat_request_schema.openai, ctx.req.body_origin)
end

-- Handle HTTP errors by returning a standard error response.
local function handle_error(err)
    core.log.error("anthropic driver error: ", err)
    return 500, { code = 500, message = "Internal Server Error" }
end

-- Translate the OpenAI request format to the Anthropic format.
local function translate_request_to_anthropic(request_table, model_options)
    local system_prompt = ""
    local user_messages = {}

    for _, msg in ipairs(request_table.messages) do
        if msg.role == "system" then
            system_prompt = system_prompt .. msg.content .. "\n"
        else
            table.insert(user_messages, msg)
        end
    end

    local anthropic_req = {
        model = model_options.model or request_table.model,
        system = system_prompt,
        messages = user_messages,
        max_tokens = model_options.max_tokens or 4096, -- max_tokens is required by Anthropic
        stream = request_table.stream,
        temperature = model_options.temperature or request_table.temperature,
        top_p = model_options.top_p or request_table.top_p,
        top_k = model_options.top_k or request_table.top_k,
    }

    return anthropic_req
end

-- Translate the non-streaming Anthropic response to the OpenAI format.
local function translate_response_to_openai(anthropic_res, start_time)
    local choices = {}
    if anthropic_res.content and #anthropic_res.content > 0 then
        for i, content_block in ipairs(anthropic_res.content) do
            table.insert(choices, {
                index = i - 1,
                message = {
                    role = "assistant",
                    content = content_block.text,
                },
                finish_reason = anthropic_res.stop_reason,
            })
        end
    end

    local openai_res = {
        id = anthropic_res.id,
        object = "chat.completion",
        created = start_time,
        model = anthropic_res.model,
        choices = choices,
        usage = {
            prompt_tokens = anthropic_res.usage.input_tokens,
            completion_tokens = anthropic_res.usage.output_tokens,
            total_tokens = (anthropic_res.usage.input_tokens or 0) + (anthropic_res.usage.output_tokens or 0),
        },
    }

    return openai_res
end

-- Process the streaming response from Anthropic.
local function read_stream_response(ctx, res)
    local stream_parser = sse.new()
    local start_time = ngx.time()
    local model_name = ""

    while true do
        local chunk, err = res:read_chunk()
        if err then
            core.log.error("failed to read stream chunk: ", err)
            return handle_error(err)
        end

        if not chunk or chunk == "" then
            break
        end

        local events, err = stream_parser:parse(chunk)
        if err then
            core.log.error("failed to parse SSE stream: ", err)
            return handle_error(err)
        end

        for _, event in ipairs(events) do
            if event.type == "message_start" then
                model_name = event.data.message.model
            elseif event.type == "content_block_delta" then
                local delta = event.data.delta
                if delta and delta.text then
                    local openai_chunk = {
                        id = "chatcmpl-" .. core.utils.random_string(24),
                        object = "chat.completion.chunk",
                        created = start_time,
                        model = model_name,
                        choices = {{
                            index = 0,
                            delta = { content = delta.text },
                            finish_reason = nil,
                        }},
                    }
                    plugin.lua_response_filter(ctx, {}, "data: " .. core.json.encode(openai_chunk) .. "\n\n")
                end
            elseif event.type == "message_stop" then
                local final_chunk = {
                    id = "chatcmpl-" .. core.utils.random_string(24),
                    object = "chat.completion.chunk",
                    created = start_time,
                    model = model_name,
                    choices = {{
                        index = 0,
                        delta = {},
                        finish_reason = "stop",
                    }},
                }
                plugin.lua_response_filter(ctx, {}, "data: " .. core.json.encode(final_chunk) .. "\n\n")
                plugin.lua_response_filter(ctx, {}, "data: [DONE]\n\n")
            end
        end
    end

    return 200
end

-- Main request function for the driver.
function _M.request(self, ctx, conf, request_table, extra_opts)
    local httpc, err = http.new()
    if not httpc then
        return handle_error("failed to create http client")
    end

    httpc:set_timeout(conf.timeout)

    local anthropic_req = translate_request_to_anthropic(request_table, extra_opts.model_options or {})

    local headers = extra_opts.headers or {}
    headers["anthropic-version"] = (extra_opts.model_options and extra_opts.model_options.anthropic_version) or "2023-06-01"
    headers["Content-Type"] = "application/json"

    local res, err = httpc:request({
        method = "POST",
        path = self.path,
        host = self.host,
        port = self.port,
        ssl_verify = conf.ssl_verify,
        headers = headers,
        body = core.json.encode(anthropic_req),
    })

    if not res then
        return handle_error(err)
    end

    if res.status >= 300 then
        local body, read_err = res:read_body()
        if read_err then
            return handle_error(read_err)
        end
        core.log.error("anthropic api error, status: ", res.status, ", body: ", body)
        return res.status, body
    end

    if request_table.stream then
        return read_stream_response(ctx, res)
    else
        local body, read_err = res:read_body()
        if read_err then
            return handle_error(read_err)
        end

        local anthropic_res, json_err = core.json.decode(body)
        if json_err then
            return handle_error("failed to decode anthropic response: " .. json_err)
        end

        local openai_res = translate_response_to_openai(anthropic_res, ctx.llm_request_start_time)
        return 200, core.json.encode(openai_res)
    end
end

return _M
