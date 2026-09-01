# Every listener we pin ourselves. Kept in the ephemeral range (49152-65535) unless the service
# dictates otherwise, so we never squat on a port some other tool reasonably expects to own.
{
  litellm = 61175; # OpenAI-compatible router: `clc` and the openclaw gateway both dial this
  litellmMixed = 61176; # second router, own config -- `clm` needs Opus and Luna behind one base url
  openclawGateway = 18789; # WebSocket gateway + control UI
}
