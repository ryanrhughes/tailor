/**
 * Beads Plugin for OpenCode
 *
 * Integrates beads (bd) issue tracker with OpenCode, providing:
 * - Automatic context injection on session start via `bd prime`
 * - Context preservation during compaction
 * - Session completion notifications
 *
 * This uses the CLI + hooks approach (recommended) which is more
 * context-efficient (~1-2k tokens) compared to MCP server (~10-50k tokens).
 *
 * Prerequisites:
 * - Install bd: brew install steveyegge/beads/bd
 * - Initialize in project: bd init --quiet
 * - Install git hooks: bd hooks install
 *
 * @see https://github.com/steveyegge/beads
 */

import type { Plugin } from "@opencode-ai/plugin"

export const BeadsPlugin: Plugin = async ({ $, directory }) => {
  // Check if bd is available and project is initialized
  const isBdAvailable = async (): Promise<boolean> => {
    try {
      await $`which bd`.quiet()
      return true
    } catch {
      return false
    }
  }

  const isBeadsInitialized = async (): Promise<boolean> => {
    try {
      await $`test -d ${directory}/.beads`.quiet()
      return true
    } catch {
      return false
    }
  }

  const getBdPrime = async (): Promise<string | null> => {
    try {
      const result = await $`bd prime`.text()
      return result.trim()
    } catch (error) {
      console.error("[beads] Failed to run bd prime:", error)
      return null
    }
  }

  // Pre-check availability
  const bdAvailable = await isBdAvailable()
  const beadsInitialized = await isBeadsInitialized()

  if (!bdAvailable) {
    console.warn("[beads] bd command not found. Install with: brew install steveyegge/beads/bd")
    return {}
  }

  if (!beadsInitialized) {
    console.warn("[beads] Beads not initialized in this project. Run: bd init --quiet")
    return {}
  }

  console.log("[beads] Plugin initialized for", directory)

  return {
    // Inject bd prime context on session start (equivalent to SessionStart hook)
    event: async ({ event }) => {
      if (event.type === "session.created") {
        console.log("[beads] New session created, injecting workflow context...")
        const primeContext = await getBdPrime()
        if (primeContext) {
          console.log("[beads] Workflow context ready (~1-2k tokens)")
        }
      }

      // Notify on session completion (optional: desktop notification)
      if (event.type === "session.idle") {
        // Uncomment for desktop notifications on Linux:
        // await $`notify-send "OpenCode" "Session completed - remember to run bd sync"`.quiet().catch(() => {})
      }
    },

    // Preserve beads context during compaction (equivalent to PreCompact hook)
    "experimental.session.compacting": async (_input, output) => {
      console.log("[beads] Session compacting, preserving workflow context...")
      const primeContext = await getBdPrime()

      if (primeContext) {
        output.context.push(`## Beads Task Tracking

${primeContext}

**Workflow reminder:**
- Use \`bd ready\` to find available work
- Use \`bd create "Title" -p <priority>\` to track new issues
- Use \`bd close <id> --reason "..."\` when completing work
- Use \`bd sync\` at end of session to commit/push`)
      }
    },
  }
}
