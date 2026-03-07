// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/x12_translator"
import topbar from "../vendor/topbar"

// Custom LiveView Hooks
const Hooks = {}

console.log("🚀 app.js loading...")

Hooks.RemoteUrlInput = {
  mounted() {
    console.log("✅ RemoteUrlInput hook mounted")

    // Aggressively disable all autocomplete features
    this.el.setAttribute('autocomplete', 'off')
    this.el.setAttribute('autocorrect', 'off')
    this.el.setAttribute('autocapitalize', 'off')
    this.el.setAttribute('spellcheck', 'false')
    this.el.setAttribute('data-form-type', 'other')
    this.el.setAttribute('data-lpignore', 'true') // LastPass ignore

    // Force clear on mount and after a delay (for browser autocomplete)
    this.el.value = ""
    setTimeout(() => { this.el.value = "" }, 100)
    setTimeout(() => { this.el.value = "" }, 500)

    // Prevent LiveView from interfering
    this.el.setAttribute('data-phx-update', 'ignore')

    // Allow normal input behavior
    this.el.addEventListener('input', (e) => {
      console.log("Input value:", e.target.value)
    })

    // Clear any browser-filled values on focus
    this.el.addEventListener('focus', () => {
      if (this.el.value && this.el.value.includes('github.com')) {
        console.log("Clearing browser-filled value")
        this.el.value = ""
      }
    })
  },
  updated() {
    // If LiveView tries to update, force clear again
    if (this.el.value !== "") {
      console.log("LiveView tried to update, forcing clear")
      this.el.value = ""
    }
  }
}

Hooks.SyncScroll = {
  mounted() {
    // Find both scrollable panels within this container
    const panels = this.el.querySelectorAll('[data-sync-scroll]')
    if (panels.length !== 2) return

    let isSyncing = false

    panels.forEach((panel, index) => {
      panel.addEventListener('scroll', () => {
        if (isSyncing) return
        isSyncing = true

        const otherPanel = panels[index === 0 ? 1 : 0]

        // Calculate scroll percentage
        const scrollPercentage = panel.scrollTop / (panel.scrollHeight - panel.clientHeight)

        // Apply same percentage to other panel
        const otherScrollTop = scrollPercentage * (otherPanel.scrollHeight - otherPanel.clientHeight)
        otherPanel.scrollTop = otherScrollTop

        // Reset sync flag after a small delay to allow smooth scrolling
        requestAnimationFrame(() => {
          isSyncing = false
        })
      })
    })
  }
}

Hooks.X12Textarea = {
  mounted() {
    console.log("✅ X12Textarea hook MOUNTED on element:", this.el.id)

    // Listen for user input to sync back to server
    this.el.addEventListener("input", (e) => {
      console.log("📝 User typed in textarea, length:", e.target.value.length)
      this.pushEvent("update_content", {content: e.target.value})
    })

    // Listen for server events to update textarea
    this.handleEvent("load_x12_content", ({content}) => {
      console.log("🎯 RECEIVED load_x12_content event in hook! Content length:", content?.length)
      console.log("📄 First 100 chars:", content.substring(0, 100))
      this.el.value = content
      console.log("✅ Textarea value updated! New length:", this.el.value.length)
    })

    console.log("🔧 Hook setup complete, waiting for events...")
  }
}

console.log("📦 Hooks object:", Hooks)
console.log("📦 colocatedHooks:", colocatedHooks)

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const mergedHooks = {...colocatedHooks, ...Hooks}
console.log("🔗 Merged hooks:", Object.keys(mergedHooks))

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: mergedHooks
})

console.log("🌐 LiveSocket created with hooks:", liveSocket)

// Handle copy to clipboard
window.addEventListener("phx:copy-to-clipboard", (e) => {
  if (e.detail.text) {
    navigator.clipboard.writeText(e.detail.text)
      .then(() => console.log("Copied to clipboard"))
      .catch(err => console.error("Failed to copy:", err))
  }
})

// Handle file download
window.addEventListener("phx:download", (e) => {
  const {filename, content} = e.detail
  if (filename && content) {
    const blob = new Blob([content], {type: "application/json"})
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = filename
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(url)
    console.log("Downloaded:", filename)
  }
})

// Handle ZIP file download (base64 encoded)
window.addEventListener("phx:download_zip", (e) => {
  const {filename, content} = e.detail
  if (filename && content) {
    // Decode base64 to binary
    const binaryString = atob(content)
    const bytes = new Uint8Array(binaryString.length)
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i)
    }

    const blob = new Blob([bytes], {type: "application/zip"})
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = filename
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(url)
    console.log("Downloaded ZIP:", filename)
  }
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

