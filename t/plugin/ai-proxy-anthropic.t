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
                "model": "claude-opus-4-5",
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
          name: claude-opus-4-5
        auth:
          header:
            x-api-key: "DUMMY_KEY"
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      scheme: http
--- request
POST /anthropic/chat/completions
{
    "model": "claude-opus-4-5",
    "messages": [
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Hello"}
    ]
}
--- response_body_like
^{"id":"msg_013Z5S7fEE4s3yA22b5c8x9f","object":"chat.completion",.+,"model":"claude-opus-4-5","choices":.+,"usage":{"prompt_tokens":10,"completion_tokens":20,"total_tokens":30}}
--- error_log




=== TEST 2: ai-proxy with anthropic provider - streaming
--- config
    location /anthropic_mock_stream {
        content_by_lua_block {
            ngx.say("event: message_start\ndata: {\"type\": \"message_start\", \"message\": {\"id\": \"msg_stream_123\", \"type\": \"message\", \"role\": \"assistant\", \"content\": [], \"model\": \"claude-opus-4-5\", \"usage\": {\"input_tokens\": 25}}}\n\n")
            ngx.say("event: content_block_start\ndata: {\"type\": \"content_block_start\", \"index\": 0, \"content_block\": {\"type\": \"text\", \"text\": \"\"}}\n\n")
            ngx.say("event: content_block_delta\ndata: {\"type\": \"content_block_delta\", \"index\": 0, \"delta\": {\"type\": \"text_delta\", \"text\": \"Hello\"}}\n\n")
            ngx.say("event: content_block_delta\ndata: {\"type\": \"content_block_delta\", \"index\": 0, \"delta\": {\"type\": \"text_delta\", \"text\": \" world!\"}}\n\n")
            ngx.say("event: message_delta\ndata: {\"type\": \"message_delta\", \"delta\": {\"stop_reason\": \"end_turn\", \"stop_sequence\":null}, \"usage\":{\"output_tokens\": 30}}\n\n")
            ngx.say("event: message_stop\ndata: {\"type\": \"message_stop\"}\n\n")
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
          name: claude-opus-4-5
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      scheme: http
--- request
POST /anthropic/chat/completions/stream
{
    "model": "claude-opus-4-5",
    "messages": [
        {"role": "user", "content": "Hello"}
    ],
    "stream": true
}
--- response_body_like
data: {"id":"msg_stream_123","object":"chat.completion.chunk",.+,"choices":.+"role":"assistant","content":""}}

data: {"id":"msg_stream_123","object":"chat.completion.chunk",.+,"choices":.+"content":"Hello"}}

data: {"id":"msg_stream_123","object":"chat.completion.chunk",.+,"choices":.+"content":" world!"}}

data: {"id":"msg_stream_123","object":"chat.completion.chunk",.+,"choices":.+"finish_reason":"end_turn"}}

data: [DONE]

--- error_log
ai-proxy.anthropic header_filter phase for stream




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
          name: claude-opus-4-5
    upstream:
      nodes:
        "127.0.0.1:1980": 1
      scheme: http
--- request
POST /anthropic/chat/completions/error
{
    "model": "claude-opus-4-5",
    "messages": [
        {"role": "user", "content": "Hello"}
    ]
}
--- status: 400
--- response_body_like
^{"error":{"message":"Invalid request","type":"invalid_request_error"}}
--- error_log

