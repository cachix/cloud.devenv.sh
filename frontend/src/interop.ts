import "./index.css";
import hljs from "highlight.js/lib/core";
import nix from "highlight.js/lib/languages/nix";
import "highlight.js/styles/github-dark.css";

// Register Nix language
hljs.registerLanguage("nix", nix);

// No longer needed - Elm handles scroll optimization internally

// SSE Connection Manager class
class SSEConnectionManager {
  private connections = new Map<string, EventSource>();
  private connectionStates = new Map<
    string,
    {
      url: string;
      handlers: {
        onOpen?: () => void;
        onMessage?: (data: any) => void;
        onError?: (error: string) => void;
      };
      retryCount: number;
      retryTimeout?: number;
      isConnecting: boolean;
      messageBuffer?: any[];
      batchTimeout?: number;
    }
  >();

  private readonly RETRY_DELAY = 5000; // 5 seconds fixed retry delay

  connect(
    id: string,
    url: string,
    handlers: {
      onOpen?: () => void;
      onMessage?: (data: any) => void;
      onError?: (error: string) => void;
    },
  ): void {
    // Clear any existing retry timeout
    const existingState = this.connectionStates.get(id);
    if (existingState?.retryTimeout) {
      clearTimeout(existingState.retryTimeout);
    }

    // Close existing connection if any
    this.disconnect(id, false);

    // Initialize or update connection state
    this.connectionStates.set(id, {
      url,
      handlers,
      retryCount: existingState?.retryCount || 0,
      isConnecting: true,
    });

    this._createConnection(id);
  }

  private _createConnection(id: string): void {
    const state = this.connectionStates.get(id);
    if (!state || !state.isConnecting) return;

    // Defer EventSource creation to next tick to prevent blocking
    setTimeout(() => {
      // Re-check state in case it changed
      if (!state.isConnecting) return;

      try {
        // Create new SSE connection
        const eventSource = new EventSource(state.url);
        this.connections.set(id, eventSource);

        eventSource.onopen = () => {
          // Reset retry count on successful connection
          state.retryCount = 0;
          state.handlers.onOpen?.();
        };

        eventSource.onmessage = (event) => {
          try {
            const data = JSON.parse(event.data);

            // Initialize message buffer if needed
            if (!state.messageBuffer) {
              state.messageBuffer = [];
            }

            // Add to buffer
            state.messageBuffer.push(data);

            // Clear existing timeout if any
            if (state.batchTimeout) {
              clearTimeout(state.batchTimeout);
            }

            // Set new timeout to batch messages
            state.batchTimeout = window.setTimeout(() => {
              if (state.messageBuffer && state.messageBuffer.length > 0) {
                // Send all buffered messages as an array
                state.handlers.onMessage?.(state.messageBuffer);
                state.messageBuffer = [];
              }
              state.batchTimeout = undefined;
            }, 16); // ~60fps, good balance between responsiveness and performance
          } catch (err) {
            console.error("Error parsing SSE message:", err, event.data);
          }
        };

        eventSource.onerror = (err) => {
          // Log more detailed error information
          console.error("SSE error details:", {
            id,
            url: state.url,
            readyState: eventSource.readyState,
            readyStateText: ["CONNECTING", "OPEN", "CLOSED"][
              eventSource.readyState
            ],
            error: err,
            retryCount: state.retryCount,
          });

          // Don't retry if manually disconnected
          if (!state.isConnecting) return;

          // Close the failed connection
          const connection = this.connections.get(id);
          if (connection) {
            connection.close();
            this.connections.delete(id);
          }

          // Simple retry with fixed delay
          state.retryCount++;

          console.log(
            `Retrying SSE connection ${id} in ${this.RETRY_DELAY}ms (attempt ${state.retryCount})`,
          );

          // Schedule retry
          state.retryTimeout = window.setTimeout(() => {
            this._createConnection(id);
          }, this.RETRY_DELAY);
        };
      } catch (error) {
        console.error("Failed to create EventSource:", error);
        state.handlers.onError?.("Failed to create connection");
        this.connectionStates.delete(id);
      }
    }, 0);
  }

  disconnect(id: string, clearState: boolean = true): void {
    const connection = this.connections.get(id);
    if (connection) {
      // Remove all event listeners before closing
      connection.onopen = null;
      connection.onmessage = null;
      connection.onerror = null;
      connection.close();
      this.connections.delete(id);
    }

    // Clear connection state and any pending retry
    const state = this.connectionStates.get(id);
    if (state) {
      state.isConnecting = false;
      if (state.retryTimeout) {
        clearTimeout(state.retryTimeout);
      }
      if (state.batchTimeout) {
        clearTimeout(state.batchTimeout);
      }
      // Flush any remaining messages as an array
      if (state.messageBuffer && state.messageBuffer.length > 0) {
        state.handlers.onMessage?.(state.messageBuffer);
        state.messageBuffer = [];
      }
      if (clearState) {
        this.connectionStates.delete(id);
      }
    }
  }

  disconnectAll(): void {
    // Use the disconnect method for each connection to ensure proper cleanup
    const ids = Array.from(this.connections.keys());
    ids.forEach((id) => this.disconnect(id));
  }
}

interface RequiredEnvVars {
  OAUTH_CLIENT_ID: string;
  OAUTH_AUDIENCE: string;
  BASE_URL: string;
}

function validateRequiredEnvVars(env: any): RequiredEnvVars {
  const requiredVars = ["OAUTH_CLIENT_ID", "OAUTH_AUDIENCE", "BASE_URL"];
  const missing = requiredVars.filter((varName) => !env[varName]);

  if (missing.length > 0) {
    throw new Error(
      `Missing required environment variables: ${missing.join(", ")}`,
    );
  }

  return {
    OAUTH_CLIENT_ID: env.OAUTH_CLIENT_ID,
    OAUTH_AUDIENCE: env.OAUTH_AUDIENCE,
    BASE_URL: env.BASE_URL,
  };
}

// This is called BEFORE your Elm app starts up
//
// The value returned here will be passed as flags
// into your `Shared.init` function.
export const flags = ({ env }: { env: any }): any => {
  let validatedEnv = validateRequiredEnvVars(env);

  let oauth = {
    clientId: validatedEnv.OAUTH_CLIENT_ID,
    audience: validatedEnv.OAUTH_AUDIENCE,
    state: rememberedBytes(),
  };

  let authData = getAuthData();
  let userInfo = getUserInfo();
  let theme = getTheme();

  return {
    now: Date.now(),
    baseUrl: validatedEnv.BASE_URL,
    authData,
    userInfo,
    oauth,
    theme,
  };
};

// This is called AFTER your Elm app starts up
//
// Here you can work with `app.ports` to send messages
// to your Elm application, or subscribe to incoming
// messages from Elm
export const onReady = ({ app, env }: { app: any; env: any }): void => {
  // Create SSE connection manager instance
  const sseManager = new SSEConnectionManager();

  // Initialize syntax highlighting for any existing code blocks
  hljs.highlightAll();

  // Handle ports for SSE
  if (app.ports) {
    if (app.ports.connectSSE) {
      app.ports.connectSSE.subscribe(
        ({ id, url }: { id: string; url: string }) => {
          sseManager.connect(id, url, {
            onOpen: () => {
              if (app.ports.sseConnected) {
                app.ports.sseConnected.send(null);
              }
            },
            onMessage: (data) => {
              if (app.ports.sseMessages) {
                app.ports.sseMessages.send(data);
              }
            },
            onError: (error) => {
              if (app.ports.sseError) {
                app.ports.sseError.send(error);
              }
            },
          });
        },
      );
    }

    if (app.ports.disconnectSSE) {
      app.ports.disconnectSSE.subscribe((id: string) => {
        sseManager.disconnect(id);

        // Clean up scroll listener
        const element = document.getElementById(`log-viewer-${id}`);
        if (element && (element as any)._scrollHandler) {
          element.removeEventListener(
            "scroll",
            (element as any)._scrollHandler,
          );
          delete (element as any)._scrollHandler;
        }
      });
    }

    if (app.ports.scrollControl) {
      app.ports.scrollControl.subscribe(
        ({ id, action }: { id: string; action: string }) => {
          requestAnimationFrame(() => {
            const element = document.getElementById(`log-viewer-${id}`);
            if (element) {
              switch (action) {
                case "bottom":
                  element.scrollTop = element.scrollHeight;
                  break;
                case "top":
                  element.scrollTop = 0;
                  break;
                case "update":
                  if (app.ports.scrollPositionChanged) {
                    app.ports.scrollPositionChanged.send({
                      scrollTop: element.scrollTop,
                      scrollHeight: element.scrollHeight,
                      clientHeight: element.clientHeight,
                    });
                  }
                  break;
              }
            }
          });
        },
      );
    }

    if (app.ports.setupScrollListener) {
      app.ports.setupScrollListener.subscribe((id: string) => {
        // Use setTimeout to ensure DOM is ready
        setTimeout(() => {
          const element = document.getElementById(`log-viewer-${id}`);
          if (element) {
            let scrollTimeout: number | undefined;

            const handleScroll = () => {
              // Clear any existing timeout
              if (scrollTimeout) {
                clearTimeout(scrollTimeout);
              }

              // Send immediate scroll position update for virtual scrolling
              const scrollTop = element.scrollTop;
              const scrollHeight = element.scrollHeight;
              const clientHeight = element.clientHeight;

              if (app.ports.scrollPositionChanged) {
                app.ports.scrollPositionChanged.send({
                  scrollTop: scrollTop,
                  scrollHeight: scrollHeight,
                  clientHeight: clientHeight,
                });
              }

              // Debounce the "at bottom" check to avoid flooding Elm
              scrollTimeout = window.setTimeout(() => {
                // Check if user is at the bottom (with 10px tolerance)
                const isAtBottom =
                  scrollTop + clientHeight >= scrollHeight - 10;

                if (app.ports.userScrolled) {
                  app.ports.userScrolled.send(isAtBottom);
                }
              }, 100);
            };

            element.addEventListener("scroll", handleScroll);

            // Store the handler so we can remove it later if needed
            (element as any)._scrollHandler = handleScroll;

            // Send initial scroll position
            if (app.ports.scrollPositionChanged) {
              app.ports.scrollPositionChanged.send({
                scrollTop: element.scrollTop,
                scrollHeight: element.scrollHeight,
                clientHeight: element.clientHeight,
              });
            }
          }
        }, 100); // Small delay to ensure DOM is ready
      });
    }

    if (app.ports.updateUrlHash) {
      app.ports.updateUrlHash.subscribe((hash: string) => {
        // Update the URL hash without triggering a page reload
        if (hash) {
          window.location.hash = hash;
        } else {
          // Clear the hash
          history.replaceState(
            null,
            "",
            window.location.pathname + window.location.search,
          );
        }
      });
    }

    if (app.ports.requestFullscreen) {
      app.ports.requestFullscreen.subscribe((id: string) => {
        const element = document.getElementById(`log-viewer-${id}`);
        if (element) {
          // Get the outermost container (parent of the white/dark background container)
          const container = element.closest(
            ".bg-white.dark\\:bg-gray-900",
          )?.parentElement;
          if (container) {
            // Add fullscreen styles to ensure full height
            container.style.height = "100vh";
            container.style.display = "flex";
            container.style.flexDirection = "column";

            // Cross-browser fullscreen request
            const elem = container as any;
            if (elem.requestFullscreen) {
              elem.requestFullscreen();
            } else if (elem.webkitRequestFullscreen) {
              elem.webkitRequestFullscreen();
            } else if (elem.mozRequestFullScreen) {
              elem.mozRequestFullScreen();
            } else if (elem.msRequestFullscreen) {
              elem.msRequestFullscreen();
            }
          }
        }
      });
    }

    if (app.ports.exitFullscreen) {
      app.ports.exitFullscreen.subscribe(() => {
        // Cross-browser exit fullscreen
        const doc = document as any;
        if (doc.exitFullscreen) {
          doc.exitFullscreen();
        } else if (doc.webkitExitFullscreen) {
          doc.webkitExitFullscreen();
        } else if (doc.mozCancelFullScreen) {
          doc.mozCancelFullScreen();
        } else if (doc.msExitFullscreen) {
          doc.msExitFullscreen();
        }
      });
    }

    // Listen for fullscreen changes
    const fullscreenChangeHandler = () => {
      const doc = document as any;
      const isFullscreen = !!(
        doc.fullscreenElement ||
        doc.webkitFullscreenElement ||
        doc.mozFullScreenElement ||
        doc.msFullscreenElement
      );

      // Clean up styles when exiting fullscreen
      if (!isFullscreen) {
        const containers = document.querySelectorAll('[id^="log-viewer-"]');
        containers.forEach((el) => {
          const container = el.closest(
            ".bg-white.dark\\:bg-gray-900",
          )?.parentElement;
          if (container && container instanceof HTMLElement) {
            container.style.height = "";
            container.style.display = "";
            container.style.flexDirection = "";
          }
        });
      }

      if (app.ports.fullscreenChanged) {
        app.ports.fullscreenChanged.send(isFullscreen);
      }
    };

    // Add fullscreen change listeners for different browsers
    document.addEventListener("fullscreenchange", fullscreenChangeHandler);
    document.addEventListener(
      "webkitfullscreenchange",
      fullscreenChangeHandler,
    );
    document.addEventListener("mozfullscreenchange", fullscreenChangeHandler);
    document.addEventListener("MSFullscreenChange", fullscreenChangeHandler);
  }

  if (app.ports && app.ports.outgoing) {
    app.ports.outgoing.subscribe(
      ({ tag, data }: { tag: string; data: any }) => {
        switch (tag) {
          case "GEN_RANDOM_BYTES":
            const buffer = new Uint8Array(data);
            crypto.getRandomValues(buffer);
            const bytes = Array.from(buffer);
            localStorage.setItem("bytes", JSON.stringify(bytes));
            app.ports.incoming.send({ tag: "GOT_RANDOM_BYTES", data: bytes });
            break;
          case "SEND_TO_LOCAL_STORAGE":
            localStorage.setItem(data.key, JSON.stringify(data.value));
            break;
          case "SET_THEME":
            // Don't send the event back to Elm if it matches the current theme
            const currentTheme = document.documentElement.classList.contains(
              "dark",
            )
              ? "dark"
              : "light";
            if (currentTheme !== data.theme) {
              setTheme(data.theme);
              // We won't send THEME_CHANGED back to Elm to avoid circular events
            }
            break;
          default:
            console.warn(`Unhandled outgoing port: "${tag}"`);
            return;
        }
      },
    );
  }

  // Set initial theme
  applyTheme(getTheme());
};

// Fetch bytes for PKCE from local storage
function rememberedBytes(): number[] | null {
  const bytes = localStorage.getItem("bytes");
  return bytes ? JSON.parse(bytes) : null;
}

function getAuthData(): any {
  try {
    const rawAuthData = localStorage.getItem("authData");
    if (!rawAuthData) return null;

    const authData = JSON.parse(rawAuthData);
    return authData?.token ? authData : null;
  } catch (e) {
    return null;
  }
}

function getUserInfo(): any {
  try {
    const rawUserInfo = localStorage.getItem("userInfo");
    if (!rawUserInfo) return null;
    return JSON.parse(rawUserInfo);
  } catch (e) {
    return null;
  }
}

// Theme management
function getTheme(): string {
  const savedTheme = localStorage.getItem("theme");
  if (savedTheme) return JSON.parse(savedTheme);

  // If no theme is saved, check system preference
  if (
    window.matchMedia &&
    window.matchMedia("(prefers-color-scheme: dark)").matches
  ) {
    return "dark";
  }

  return "light";
}

function setTheme(theme: string): void {
  localStorage.setItem("theme", JSON.stringify(theme));
  applyTheme(theme);
}

// Track theme change state to prevent multiple simultaneous transitions
let isThemeChanging = false;

// Theme change handling
function applyTheme(theme: string): void {
  // Skip if a theme change is already in progress
  if (isThemeChanging) return;

  // Set flag to prevent multiple theme changes
  isThemeChanging = true;

  // Use requestAnimationFrame for smoother transitions
  window.requestAnimationFrame(() => {
    // First set a data attribute to allow CSS transitions to target this state
    document.documentElement.setAttribute("data-theme-transition", "true");

    // Apply the theme class
    document.documentElement.classList.toggle("dark", theme === "dark");
    document.documentElement.classList.toggle("light", theme === "light");

    // Remove the transition attribute after transitions complete
    setTimeout(() => {
      document.documentElement.removeAttribute("data-theme-transition");
      isThemeChanging = false; // Reset flag after transition completes
    }, 300); // Match this to your CSS transition duration
  });
}
