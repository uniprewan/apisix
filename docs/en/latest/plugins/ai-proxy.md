---
title: ai-proxy
keywords:
  - Apache APISIX
  - API Gateway
  - Plugin
  - ai-proxy
  - AI
  - LLM
description: The ai-proxy Plugin simplifies access to LLM and embedding models providers by converting Plugin configurations into the required request format for OpenAI, DeepSeek, Azure, AIMLAPI, Anthropic, OpenRouter, and other OpenAI-compatible APIs.
---

<!--
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
-->

<head>
  <link rel="canonical" href="https://docs.api7.ai/hub/ai-proxy" />
</head>

## Description

The `ai-proxy` Plugin simplifies access to LLM and embedding models by transforming Plugin configurations into the designated request format. It supports the integration with OpenAI, DeepSeek, Azure, AIMLAPI, Anthropic, OpenRouter, and other OpenAI-compatible APIs.

In addition, the Plugin also supports logging LLM request information in the access log, such as token usage, model, time to the first response, and more.

## Request Format

| Name               | Type   | Required | Description                                         |
| ------------------ | ------ | -------- | --------------------------------------------------- |
| `messages`         | Array  | True      | An array of message objects.                        |
| `messages.role`    | String | True      | Role of the message (`system`, `user`, `assistant`).|
| `messages.content` | String | True      | Content of the message.                             |

## Attributes

| Name               | Type    | Required | Default | Valid values                              | Description |
|--------------------|--------|----------|---------|------------------------------------------|-------------|
| provider          | string  | True     |         | [openai, deepseek, azure-openai, aimlapi, anthropic, openrouter, openai-compatible] | LLM service provider. When set to `openai`, the Plugin will proxy the request to `https://api.openai.com/chat/completions`. When set to `deepseek`, the Plugin will proxy the request to `https://api.deepseek.com/chat/completions`. When set to `aimlapi`, the Plugin uses the OpenAI-compatible driver and proxies the request to `https://api.aimlapi.com/v1/chat/completions` by default. When set to `anthropic`, the Plugin will proxy the request to `https://api.anthropic.com/v1/messages` by default. When set to `openrouter`, the Plugin uses the OpenAI-compatible driver and proxies the request to `https://openrouter.ai/api/v1/chat/completions` by default. When set to `openai-compatible`, the Plugin will proxy the request to the custom endpoint configured in `override`. |
| auth             | object  | True     |         |                                          | Authentication configurations. |
| auth.header      | object  | False    |         |                                          | Authentication headers. At least one of `header` or `query` must be configured. |
| auth.query       | object  | False    |         |                                          | Authentication query parameters. At least one of `header` or `query` must be configured. |
| options         | object  | False    |         |                                          | Model configurations. In addition to `model`, you can configure additional parameters and they will be forwarded to the upstream LLM service in the request body. For instance, if you are working with OpenAI, you can configure additional parameters such as `temperature`, `top_p`, and `stream`. See your LLM provider's API documentation for more available options.  |
| options.model   | string  | False    |         |                                          | Name of the LLM model, such as `gpt-4` or `gpt-3.5`. Refer to the LLM provider's API documentation for available models. |
| override        | object  | False    |         |                                          | Override setting. |
| override.endpoint | string | False    |         |                                          | Custom LLM provider endpoint, required when `provider` is `openai-compatible`. |
| logging        | object  | False    |         |                                          | Logging configurations. |
| logging.summaries | boolean | False | false |                                          | If true, logs request LLM model, duration, request, and response tokens. |
| logging.payloads  | boolean | False | false |                                          | If true, logs request and response payload. |
| timeout        | integer | False    | 30000    | ≥ 1                                      | Request timeout in milliseconds when requesting the LLM service. |
| keepalive      | boolean | False    | true   |                                          | If true, keeps the connection alive when requesting the LLM service. |
| keepalive_timeout | integer | False | 60000  | ≥ 1000                                   | Keepalive timeout in milliseconds when connecting to the LLM service. |
| keepalive_pool | integer | False    | 30       |                                          | Keepalive pool size for the LLM service connection. |
| ssl_verify     | boolean | False    | true   |                                          | If true, verifies the LLM service's certificate. |

## Examples

The examples below demonstrate how you can configure `ai-proxy` for different scenarios.

:::note

You can fetch the `admin_key` from `config.yaml` and save to an environment variable with the following command:

```bash
admin_key=$(yq '.deployment.admin.admin_key[0].key' conf/config.yaml | sed 's/\"//g')
```

:::

### Proxy to OpenAI

The following example demonstrates how you can configure the API key, model, and other parameters in the `ai-proxy` Plugin and configure the Plugin on a Route to proxy user prompts to OpenAI.

Obtain the OpenAI [API key](https://openai.com/blog/openai-api) and save it to an environment variable:

```shell
export OPENAI_API_KEY=<your-api-key>
```

Create a Route and configure the `ai-proxy` Plugin as such:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-openai-route",
    "uri": "/openai",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        },
        "options":{
          "model": "gpt-4"
        }
      }
    }
  }'
```

Send a POST request to the Route with a system prompt and a sample user question in the request body:

```shell
curl "http://127.0.0.1:9080/openai" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

You should receive a response similar to the following:

```json
{
  ...,
  "model": "gpt-4-0613",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "1+1 equals 2.",
        "refusal": null
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  ...
}
```

### Proxy to DeepSeek

The following example demonstrates how you can configure the `ai-proxy` Plugin to proxy requests to DeekSeek.

Obtain the DeekSeek API key and save it to an environment variable:

```shell
export DEEPSEEK_API_KEY=<your-api-key>
```

Create a Route and configure the `ai-proxy` Plugin as such:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-deepseek-route",
    "uri": "/deepseek",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "deepseek",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$DEEPSEEK_API_KEY"'"
          }
        },
        "options": {
          "model": "deepseek-chat"
        }
      }
    }
  }'
```

Send a POST request to the Route with a sample question in the request body:

```shell
curl "http://127.0.0.1:9080/deepseek" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {
        "role": "system",
        "content": "You are an AI assistant that helps people find information."
      },
      {
        "role": "user",
        "content": "Write me a 50-word introduction for Apache APISIX."
      }
    ]
  }'
```

You should receive a response similar to the following:

```json
{
  ...
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Apache APISIX is a dynamic, real-time, high-performance API gateway and cloud-native platform. It provides rich traffic management features like load balancing, dynamic upstream, canary release, circuit breaking, authentication, observability, and more. Designed for microservices and serverless architectures, APISIX ensures scalability, security, and seamless integration with modern DevOps workflows."
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  ...
}
```

### Proxy to Anthropic

The following example shows how to configure the `ai-proxy` plugin to proxy requests to Anthropic. The plugin will automatically convert the OpenAI-compatible request format to the format required by the Anthropic Messages API.

Obtain the Anthropic [API key](https://console.anthropic.com/settings/keys) and save it to an environment variable:

```shell
export ANTHROPIC_API_KEY="your-api-key"
```

Create a Route and configure the `ai-proxy` plugin. Note that for Anthropic, the `x-api-key` header is used for authentication, and `anthropic_version` and `max_tokens` are required parameters.

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-anthropic-route",
    "uri": "/anthropic",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "anthropic",
        "auth": {
          "header": {
            "x-api-key": "'"$ANTHROPIC_API_KEY"'"
          }
        },
        "options": {
          "model": "claude-opus-4-5",
          "anthropic_version": "2023-06-01",
          "max_tokens": 4096
        }
      }
    }
  }'
```

Send a POST request to the Route with a standard OpenAI-formatted message:

```shell
curl "http://127.0.0.1:9080/anthropic" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a helpful assistant that provides concise answers." },
      { "role": "user", "content": "What is Apache APISIX?" }
    ]
  }'
```

The plugin converts the request and proxies it to Anthropic. You should receive an OpenAI-compatible response similar to the following:

```json
{
  "id": "chatcmpl-8sZ...",
  "object": "chat.completion",
  "created": 1707980... ,
  "model": "claude-opus-4-5",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Apache APISIX is a high-performance, dynamic, real-time API gateway based on Nginx and etcd. It is designed to handle high-concurrency traffic and provides features like dynamic routing, plugin hot-reloading, and support for various protocols. It is often used in microservices architectures to manage north-south traffic."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 27,
    "completion_tokens": 78,
    "total_tokens": 105
  }
}
```

#### Anthropic Specific Parameters

When using the `anthropic` provider, you can specify additional parameters within the `options` object. These are passed to the Anthropic API.

| Name                | Type   | Required | Description |
|---------------------|--------|----------|-------------|
| `anthropic_version` | string | True     | The version of the Anthropic API to use. For example, `2025-07-15`. |
| `max_tokens`        | integer| True     | The maximum number of tokens to generate in the response. |

### Proxy to Azure OpenAI

The following example demonstrates how you can configure the `ai-proxy` Plugin to proxy requests to other LLM services, such as Azure OpenAI.

Obtain the Azure OpenAI API key and save it to an environment variable:

```shell
export AZ_OPENAI_API_KEY=<your-api-key>
```

Create a Route and configure the `ai-proxy` Plugin as such:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-azure-route",
    "uri": "/azure",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "openai-compatible",
        "auth": {
          "header": {
            "api-key": "'"$AZ_OPENAI_API_KEY"'"
          }
        },
        "options":{
          "model": "gpt-4"
        },
        "override": {
          "endpoint": "https://<your-azure-resource>.openai.azure.com/openai/deployments/<your-deployment>/chat/completions?api-version=2024-02-15-preview"
        }
      }
    }
  }'
```

Send a POST request to the Route with a sample question in the request body:

```shell
curl "http://127.0.0.1:9080/azure" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {
        "role": "user",
        "content": "What are some of the key features of Apache APISIX?"
      }
    ]
  }'
```

You should receive a response similar to the following:

```json
{
  ...,
  "choices": [
    {
      "index": 0,
      "finish_reason": "stop",
      "message": {
        "role": "assistant",
        "content": "Apache APISIX has many key features, including:\n\n1.  **High Performance:** It is built on top of Nginx and provides high performance and low latency.\n2.  **Dynamic:** It supports hot loading of Plugins, which means you can enable or disable Plugins without restarting the service.\n3.  **Rich Ecosystem:** It has a rich ecosystem of Plugins for traffic management, security, and observability.\n4.  **Customizable:** You can write your own Plugins in Lua or other languages.\n5.  **Cloud-Native:** It is designed for cloud-native environments and supports containerization and orchestration platforms like Kubernetes."
      }
    }
  ],
  ...
}
```

### Enable Logging

The following example shows how you can enable logging to record the LLM request and response information in the access log.

Create a Route and configure the `ai-proxy` Plugin as such:

```shell
curl "http://127.0.0.1:9180/apisix/admin/routes" -X PUT \
  -H "X-API-KEY: ${admin_key}" \
  -d '{
    "id": "ai-proxy-route",
    "uri": "/anything",
    "methods": ["POST"],
    "plugins": {
      "ai-proxy": {
        "provider": "openai",
        "auth": {
          "header": {
            "Authorization": "Bearer '"$OPENAI_API_KEY"'"
          }
        },
        "options":{
          "model": "gpt-4"
        },
        "logging": {
          "summaries": true,
          "payloads": true
        }
      }
    }
  }'
```

Send a POST request to the Route:

```shell
curl "http://127.0.0.1:9080/anything" -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "system", "content": "You are a mathematician" },
      { "role": "user", "content": "What is 1+1?" }
    ]
  }'
```

Now if you check the `access.log` file, you should see logs similar to the following:

```text
127.0.0.1 - - [20/Sep/2023:10:00:00 +0000] 127.0.0.1:9080 "POST /anything HTTP/1.1" 200 1029 "-" "curl/8.1.2" "ai-proxy-route" "api.openai.com" 1.234 1.234 1234 1234
{"llm_summaries":[{"model":"gpt-4-0613","duration":1234,"request_tokens":21,"response_tokens":5,"response_first_chunk_duration":1000,"response_finish_duration":1234}]}
{"llm_request_payloads":[{"role":"system","content":"You are a mathematician"},{"role":"user","content":"What is 1+1?"}]}
{"llm_response_payloads":[{"role":"assistant","content":"1+1 equals 2."}]}
```
