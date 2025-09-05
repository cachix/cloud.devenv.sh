use crate::protocol::{ClientMessage, Platform, ServerMessage};
use futures_util::{SinkExt, StreamExt};
use std::time::Duration;
use thiserror::Error;
use tokio::time::timeout;
use tokio_tungstenite::{
    connect_async,
    tungstenite::{
        handshake::client::generate_key,
        http::{Request, Uri},
        protocol::Message,
    },
};

#[derive(Error, Debug)]
pub enum WebSocketError {
    #[error("WebSocket connection error: {0}")]
    ConnectionError(#[from] tokio_tungstenite::tungstenite::Error),

    #[error("JSON serialization error: {0}")]
    SerializationError(#[from] serde_json::Error),

    #[error("Connection timed out")]
    ConnectionTimeout,

    #[error("Send message timed out")]
    SendTimeout,

    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),

    #[error("Unsupported platform")]
    UnsupportedPlatform,
}

pub struct WebSocketClient {
    pub write: futures_util::stream::SplitSink<
        tokio_tungstenite::WebSocketStream<
            tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
        >,
        Message,
    >,
}

impl WebSocketClient {
    /// Creates a new WebSocketClient with the given URI
    ///
    /// # Arguments
    /// * `uri` - WebSocket server URI
    /// * `connect_timeout_secs` - Optional connection timeout in seconds (defaults to 30 seconds)
    pub async fn new(
        uri: Uri,
        connect_timeout_secs: Option<u64>,
    ) -> Result<
        (
            Self,
            impl StreamExt<Item = Result<ServerMessage, WebSocketError>>,
        ),
        WebSocketError,
    > {
        // Default timeout of 30 seconds if not specified
        let timeout_duration = Duration::from_secs(connect_timeout_secs.unwrap_or(30));

        // Determine the platform based on compile-time target and runtime check
        let platform = if cfg!(target_os = "macos") {
            if cfg!(target_arch = "aarch64") {
                Platform::AArch64Darwin
            } else {
                // We don't currently support x86_64-darwin (Intel Mac)
                tracing::error!("Unsupported platform: x86_64-darwin (Intel Mac)");
                return Err(WebSocketError::UnsupportedPlatform);
            }
        } else if cfg!(target_os = "linux") {
            if cfg!(target_arch = "x86_64") {
                Platform::X86_64Linux
            } else {
                // We don't currently support non-x86_64 Linux (e.g., aarch64-linux)
                tracing::error!("Unsupported platform: non-x86_64 Linux architecture");
                return Err(WebSocketError::UnsupportedPlatform);
            }
        } else {
            // Neither macOS nor Linux
            tracing::error!("Unsupported platform: neither macOS nor Linux");
            return Err(WebSocketError::UnsupportedPlatform);
        };

        let host = uri.host().unwrap_or("localhost");

        let request = Request::builder()
            .method("GET")
            .uri(uri.clone())
            .header("Host", host)
            .header("Upgrade", "websocket")
            .header("Connection", "upgrade")
            .header("X-Runner-Platform", platform.to_string())
            .header("Sec-Websocket-Key", generate_key())
            .header("Sec-Websocket-Version", "13")
            .body(())
            .unwrap();

        // Attempt connection with timeout
        let ws_stream = match timeout(timeout_duration, connect_async(request)).await {
            Ok(result) => result?,
            Err(_) => return Err(WebSocketError::ConnectionTimeout),
        };

        let (ws_stream, _) = ws_stream;
        let (write, read) = ws_stream.split();

        let typed_read = read.map(|message| -> Result<ServerMessage, WebSocketError> {
            let msg = message?;
            match msg {
                Message::Text(text) => Ok(serde_json::from_str(&text)?),
                Message::Binary(bytes) => Ok(serde_json::from_slice(&bytes)?),
                _ => Ok(serde_json::from_str("{}")?), // Handle other message types as empty
            }
        });

        Ok((Self { write }, typed_read))
    }

    /// Sends a message to the WebSocket server
    ///
    /// # Arguments
    /// * `message` - The client message to send
    /// * `timeout_secs` - Optional send timeout in seconds (defaults to 10 seconds)
    pub async fn send_message(
        &mut self,
        message: ClientMessage,
        timeout_secs: Option<u64>,
    ) -> Result<(), WebSocketError> {
        let serialized = serde_json::to_string(&message)?;

        // Default timeout of 10 seconds if not specified
        let timeout_duration = Duration::from_secs(timeout_secs.unwrap_or(10));

        // Attempt to send with timeout - use .into() to convert String to Utf8Bytes
        match timeout(
            timeout_duration,
            self.write.send(Message::Text(serialized.into())),
        )
        .await
        {
            Ok(result) => result?,
            Err(_) => return Err(WebSocketError::SendTimeout),
        }

        Ok(())
    }

    /// Simpler version of send_message without timeout
    pub async fn send(&mut self, message: ClientMessage) -> Result<(), WebSocketError> {
        self.send_message(message, None).await
    }

    /// Closes the WebSocket connection gracefully
    pub async fn close(&mut self) -> Result<(), WebSocketError> {
        // Send a close frame to properly close the WebSocket connection with 5 second timeout
        match timeout(Duration::from_secs(5), async {
            self.write.send(Message::Close(None)).await?;
            self.write.flush().await?;
            Ok::<(), WebSocketError>(())
        })
        .await
        {
            Ok(result) => result,
            Err(_) => {
                tracing::warn!("WebSocket close operation timed out after 5 seconds");
                Ok(()) // Don't fail shutdown on timeout
            }
        }
    }
}
