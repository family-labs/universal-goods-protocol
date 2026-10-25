#!/usr/bin/env node
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { createServer, optionsFromEnv } from './mcp-server.js';

// `ug-verify-mcp`: the MCP server over stdio. Configure it in any MCP client, for example:
//   { "command": "npx", "args": ["-y", "@universal-goods/verify", "ug-verify-mcp"] }
const server = createServer(optionsFromEnv());
await server.connect(new StdioServerTransport());
