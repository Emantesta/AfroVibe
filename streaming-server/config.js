// Streaming config
module.exports = {
  port: 8080,
  maxBitrate: '800k',
  eventStream: {
    arEnabled: true,
    latency: 'low',
    maxUsers: 10000,
    codecs: ['H264', 'VP8']
  },
  liveStream: {
    maxBitrate: '600k',
    codecs: ['H264']
  },
  security: {
    cors: ['https://afrovibe.io'],
    rateLimit: 100
  }
};
