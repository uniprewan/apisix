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


-- THIS FILE IS TEMPORARILY CREATED AND WILL BE MERGED WITH THE OFFICIAL
-- `test-ai-proxy.t` in the APISIX repository. It contains only the tests
-- for the new Anthropic provider.


run_tests();


__DATA__


=== TEST 1: ai-proxy with anthropic provider - non-streaming
--- config
    location /anthropic_mock {
        content_by_lua_block {
            local core = require("apisix.core")
            ngx.say([[{
                "id": "msg_013Z5S7fEE4s3yA22b5c8x9f",
                "type": "message",
                "role": "assistant",
                "content": [
                    {
                        "type": "text",
                        "text": "Hello from mock Anthropic!"
                    }
                ],
                "model": "claude-3-opus-20240229",
                "stop_reason": "end_turn",
                "stop_sequence": null,
                "usage": {
                    "input_tokens": 10,
                    "output_tokens": 20
                }
            }]])
        }
    }


    location /v1/chat/completions {
        proxy_pass http://127.0.0.1:$server_port/anthropic_mock;
    }
--- apisix_yaml
routes:
  - id: 1
    uri: /anthropic/chat/completions
    plugins:
      ai-proxy:
        model:
          provider: anthropic
          name: claude-3-opus-20240229
        authentication:
          api_key: "DUMMY_KEY"
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      scheme: http
--- request
POST /anthropic/chat/completions
{
    "model": "claude-3-opus-20240229",
    "messages": [
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Hello"}
    ]
}
--- response_body_like
^{\"id\":\"msg_013Z5S7fEE4s3yA22b5c8x9f\",\"object\":\"chat.completion\",.+,"model\":\"claude-3-opus-20240229\",\"choices\":.+,"usage\":{\"prompt_tokens\":10,\"completion_tokens\":20,\"total_tokens\":30}}
---




=== TEST 2: ai-proxy with anthropic provider - streaming
--- config
    location /anthropic_mock_stream {
        content_by_lua_block {
            ngx.say("event: message_start\ndata: {\\\"type\\\": \\\"message_start\\\", \\\"message\\\": {\\\"id\\\": \\\"msg_stream_123\\\", \\\"type\\\": \\\"message\\\", \\\"role\\\": \\\"assistant\\\", \\\"content\\\": [], \\\"model\\\": \\\"claude-3-opus-20240229\\\", \\\"usage\\\": {\\\"input_tokens\\\": 25}}}\n\n")
            ngx.say("event: content_block_start\ndata: {\\\"type\\\": \\\"content_block_start\\\", \\\"index\\\": 0, \\\"content_block\\\": {\\\"type\\\": \\\"text\\\", \\\"text\\\": \\\"\\\"}}\n\n")
            ngx.say("event: content_block_delta\ndata: {\\\"type\\\": \\\"content_block_delta\\\", \\\"index\\\": 0, \\\"delta\\\": {\\\"type\\\": \\\"text_delta\\\", \\\"text\\\": \\\"Hello\\\"}}\n\n")
            ngx.say("event: content_block_delta\ndata: {\\\"type\\\": \\\"content_block_delta\\\", \\\"index\\\": 0, \\\"delta\\\": {\\\"type\\\": \\\"text_delta\\\", \\\"text\\\": \\\" world!\\\"}}\n\n")
            ngx.say("event: message_delta\ndata: {\\\"type\\\": \\\"message_delta\\\", \\\"delta\\\": {\\\"stop_reason\\\": \\\"end_turn\\\", \\\"stop_sequence\\\":null}, \\\"usage\\\":{\\"output_tokens\\\": 30}}\n\n")
            ngx.say("event: message_stop\ndata: {\\\"type\\\": \\\"message_stop\\\"}\n\n")
        }
    }


    location /v1/chat/completions {
        proxy_pass http://127.0.0.1:$server_port/anthropic_mock_stream;
    }
--- apisix_yaml
routes:
  - id: 1
    uri: /anthropic/chat/completions/stream
    plugins:
      ai-proxy:
        model:
          provider: anthropic
          name: claude-3-opus-20240229
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      scheme: http
--- request
POST /anthropic/chat/completions/stream
{
    "model": "claude-3-opus-20240229",
    "messages": [
        {"role": "user", "content": "Hello"}
    ],
    "stream": true
}
--- response_body_like
data: {\"id\":\"msg_stream_123\",\"object\":\"chat.completion.chunk\",.+,"choices\":.+\"role\":\"assistant\",\"content\":\"\"}}

data: {\"id\":\"msg_stream_123\",\"object\":\"chat.completion.chunk\",.+,"choices\":.+\"content\":\"Hello\"}}

data: {\"id\":\"msg_stream_123\",\"object\":\"chat.completion.chunk\",.+,"choices\":.+\"content\":\" world!\"}}

data: {\"id\":\"msg_stream_123\",\"object\":\"chat.completion.chunk\",.+,"choices\":.+\"finish_reason\":\"end_turn\"}}

data: [DONE]

---




=== TEST 3: ai-proxy with anthropic provider - error response
--- config
    location /anthropic_mock_error {
        content_by_lua_block {
            ngx.status = 400
            ngx.say([[{
                "type": "error",
                "error": {
                    "type": "invalid_request_error",
                    "message": "Invalid request"
                }
            }]])
        }
    }


    location /v1/chat/completions {
        proxy_pass http://127.0.0.1:$server_port/anthropic_mock_error;
    }
--- apisix_yaml
routes:
  - id: 1
    uri: /anthropic/chat/completions/error
    plugins:
      ai-proxy:
        model:
          provider: anthropic
          name: claude-3-opus-20240229
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      scheme: http
--- request
POST /anthropic/chat/completions/error
{
    "model": "claude-3-opus-20240229",
    "messages": [
        {"role": "user", "content": "Hello"}
    ]
}
--- status: 400
--- response_body_like
^{\"error\":{\"message\":\"Invalid request\",\"type\":\"invalid_request_error\"}}
---


=== TEST 4: ai-proxy anthropic - verify options passing (max_tokens, temperature)
--- config
    location /anthropic_mock_params {
        content_by_lua_block {
            local core = require("apisix.core")
            local data = core.json.decode(ngx.req.get_body_data())
            if data["max_tokens"] ~= 1024 or data["temperature"] ~= 0.5 then
                ngx.status = 400
                ngx.say("Param mismatch")
                return
            end
            ngx.say([[[{"id": "msg_01", "content": [{"type": "text", "text": "Params OK"}], "usage": {"input_tokens": 5, "output_tokens": 5}}]]])
        }
    }
    location /v1/messages {
        proxy_pass http://127.0.0.1:$server_port/anthropic_mock_params;
    }
--- apisix_yaml
routes:
  - id: 1
    uri: /anthropic/params
    plugins:
      ai-proxy:
        model:
          provider: anthropic
          name: claude-3-sonnet
        options:
          max_tokens: 1024
          temperature: 0.5
        authentication:
          api_key: "test-key"
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      scheme: http
--- request
POST /anthropic/params
{"messages": [{"role": "user", "content": "hi"}]}
---


=== TEST 5: ai-proxy anthropic - handle multiple system messages
--- config
    location /anthropic_mock_system {
        content_by_lua_block {
            local core = require("apisix.core")
            local data = core.json.decode(ngx.req.get_body_data())
            -- Validation: system should be a merged string, and not in messages array
            if data["system"] == "Task 1. Task 2." and #data["messages"] == 1 then
                ngx.say([[[{"id": "msg_02", "content": [{"text": "System merged"}], "usage": {"input_tokens": 1, "output_tokens": 1}}]]])
            else
                ngx.status = 500
                ngx.say("System prompt error")
            end
        }
    }
    location /v1/messages {
        proxy_pass http://127.0.0.1:$server_port/anthropic_mock_system;
    }
--- apisix_yaml
routes:
  - id: 2
    uri: /anthropic/system-merge
    plugins:
      ai-proxy:
        model:
          provider: anthropic
          name: claude-3
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      scheme: http
--- request
POST /anthropic/system-merge
{
    "messages": [
        {"role": "system", "content": "Task 1."},
        {"role": "system", "content": "Task 2."},
        {"role": "user", "content": "Run"}
    ]
}
---


=== TEST 6: ai-proxy anthropic - verify mandatory headers
--- config
    location /anthropic_headers {
        content_by_lua_block {
            local version = ngx.req.get_headers()["anthropic-version"]
            if version == "2023-06-01" then
                ngx.say("Header OK")
            else
                ngx.status = 400
                ngx.say("Missing version header")
            end
        }
    }
    location /v1/messages {
        proxy_pass http://127.0.0.1:$server_port/anthropic_headers;
    }
--- apisix_yaml
routes:
  - id: 3
    uri: /anthropic/headers
    plugins:
      ai-proxy:
        model: { provider: anthropic, name: claude-3 }
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      scheme: http
--- request
POST /anthropic/headers
{"messages": [{"role": "user", "content": "hi"}]}
--- response_body: Header OK


=== TEST 7: ai-proxy with anthropic provider - native anthropic request format
--- config
    location /anthropic_mock_native {
        content_by_lua_block {
            local core = require("apisix.core")
            local data = core.json.decode(ngx.req.get_body_data())
            -- Validation: Ensure it's a native Anthropic request
            if data["system"] == "You are a native assistant." and data["messages"][1]["role"] == "user" then
                ngx.say([[{
                    "id": "msg_native_001",
                    "type": "message",
                    "role": "assistant",
                    "content": [{"type": "text", "text": "Native OK"}],
                    "usage": {"input_tokens": 15, "output_tokens": 5}
                }]])
            else
                ngx.status = 400
                ngx.say("Not a native format")
            end
        }
    }
    location /v1/messages {
        proxy_pass http://127.0.0.1:$server_port/anthropic_mock_native;
    }
--- apisix_yaml
routes:
  - id: 4
    uri: /anthropic/native
    plugins:
      ai-proxy:
        model:
          provider: anthropic
          name: claude-3-haiku
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      scheme: http
--- request
POST /anthropic/native
{
    "system": "You are a native assistant.",
    "messages": [
        {"role": "user", "content": "Native test"}
    ],
    "max_tokens": 100
}
--- response_body_like
^{\"id\":\"msg_native_001\",.+}
---
