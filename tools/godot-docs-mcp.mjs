// Entry point for the godot-docs MCP server.
//
// The upstream package @nuskey8/godot-docs-mcp is generated from a Deno
// codebase and is broken on Node in two ways:
//   1. its `bin` points at a raw .ts file, which Node < 22.18 cannot run,
//   2. its entry guards startup with `if (import.meta.main)`, a Deno-only
//      property that is undefined on Node < 24.2, so the server registers
//      nothing and exits immediately with code 0.
//
// Its scraping module (src/tools.ts) is plain Node code, so we import that
// directly and run the MCP server ourselves. Started through tsx, which
// compiles the TypeScript on the fly. See .mcp.json.

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import {
  getClass,
  getPage,
  searchDocs,
} from "../node_modules/@nuskey8/godot-docs-mcp/src/tools.ts";

const TOOLS = [
  {
    name: "godot_docs_search",
    description:
      "Search across all Godot documentation for classes, tutorials, and guides.",
    inputSchema: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description:
            "A search keyword for the Godot documentation. Must be in English.",
        },
      },
      required: ["query"],
    },
  },
  {
    name: "godot_docs_get_page",
    description: "Get the full content of a specific Godot documentation page.",
    inputSchema: {
      type: "object",
      properties: {
        url: {
          type: "string",
          description: "The URL or path to the Godot documentation page.",
        },
      },
      required: ["url"],
    },
  },
  {
    name: "godot_docs_get_class",
    description: "Get detailed information about a specific Godot class.",
    inputSchema: {
      type: "object",
      properties: {
        className: {
          type: "string",
          description: "The name of the Godot class to retrieve information for.",
        },
      },
      required: ["className"],
    },
  },
];

const server = new Server(
  { name: "godot-docs-mcp", version: "1.0.2" },
  { capabilities: { tools: {} } },
);

server.setRequestHandler(ListToolsRequestSchema, () => ({ tools: TOOLS }));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args = {} } = request.params;
  try {
    switch (name) {
      case "godot_docs_search": {
        if (!args.query) throw new Error("Query parameter is required");
        return text(JSON.stringify(await searchDocs(args.query)));
      }
      case "godot_docs_get_page": {
        if (!args.url) throw new Error("URL parameter is required");
        return text(await getPage(args.url));
      }
      case "godot_docs_get_class": {
        if (!args.className) throw new Error("className parameter is required");
        return text(await getClass(args.className));
      }
      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  } catch (error) {
    return {
      content: [
        {
          type: "text",
          text: `Error: ${error instanceof Error ? error.message : String(error)}`,
        },
      ],
      isError: true,
    };
  }
});

function text(value) {
  return { content: [{ type: "text", text: value }] };
}

process.on("SIGINT", async () => {
  await server.close();
  process.exit(0);
});

await server.connect(new StdioServerTransport());
console.error("Godot Docs MCP Server running on stdio");
