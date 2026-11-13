/*
 * Dongka Kongjian splash image filter for Quantumult X.
 *
 * Quantumult X configuration:
 * [rewrite_local]
 * (?i)^https?://ump\.szcdn\.creditcard\.ecitic\.com/ump/img/.+ url script-response-body https://raw.githubusercontent.com/th815/Profiles/refs/heads/main/Quantumult-X/dongkakongjian.js
 *
 * [mitm]
 * hostname = ump.szcdn.creditcard.ecitic.com
 *
 * The dimensions below refer to the image asset, not the phone screen.
 */
[rewrite_local]
(?i)^https?://ump\.szcdn\.creditcard\.ecitic\.com/ump/img/.+ url script-response-body https://raw.githubusercontent.com/th815/Profiles/refs/heads/main/Quantumult-X/dongkakongjian.js

[mitm]
hostname = ump.szcdn.creditcard.ecitic.com

const AD_WIDTH = 750;
const AD_HEIGHT = 1330;

function responseBytes() {
  const body = $response.bodyBytes;
  if (body instanceof Uint8Array) return body;
  if (body instanceof ArrayBuffer) return new Uint8Array(body);
  if (ArrayBuffer.isView(body)) {
    return new Uint8Array(body.buffer, body.byteOffset, body.byteLength);
  }
  if (Array.isArray(body)) return new Uint8Array(body);
  return null;
}

function bigEndian16(bytes, offset) {
  return (bytes[offset] << 8) | bytes[offset + 1];
}

function littleEndian16(bytes, offset) {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

function imageSize(bytes) {
  if (bytes.length >= 24 &&
      bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e &&
      bytes[3] === 0x47 && bytes[4] === 0x0d && bytes[5] === 0x0a &&
      bytes[6] === 0x1a && bytes[7] === 0x0a) {
    return {
      format: "PNG",
      width: (bytes[16] * 0x1000000 + bytes[17] * 0x10000 +
        bytes[18] * 0x100 + bytes[19]) >>> 0,
      height: (bytes[20] * 0x1000000 + bytes[21] * 0x10000 +
        bytes[22] * 0x100 + bytes[23]) >>> 0
    };
  }

  if (bytes.length >= 10 && bytes[0] === 0x47 && bytes[1] === 0x49 &&
      bytes[2] === 0x46 && bytes[3] === 0x38 &&
      (bytes[4] === 0x37 || bytes[4] === 0x39) && bytes[5] === 0x61) {
    return {
      format: "GIF",
      width: littleEndian16(bytes, 6),
      height: littleEndian16(bytes, 8)
    };
  }

  if (bytes.length >= 30 && bytes[0] === 0x52 && bytes[1] === 0x49 &&
      bytes[2] === 0x46 && bytes[3] === 0x46 && bytes[8] === 0x57 &&
      bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) {
    const type = String.fromCharCode(...bytes.subarray(12, 16));
    if (type === "VP8X") {
      return {
        format: "WebP",
        width: 1 + bytes[24] + (bytes[25] << 8) + (bytes[26] << 16),
        height: 1 + bytes[27] + (bytes[28] << 8) + (bytes[29] << 16)
      };
    }
    if (type === "VP8L" && bytes[20] === 0x2f) {
      const bits = (bytes[21] | (bytes[22] << 8) |
        (bytes[23] << 16) | (bytes[24] << 24)) >>> 0;
      return {
        format: "WebP",
        width: (bits & 0x3fff) + 1,
        height: ((bits >>> 14) & 0x3fff) + 1
      };
    }
    if (type === "VP8 " && bytes[23] === 0x9d &&
        bytes[24] === 0x01 && bytes[25] === 0x2a) {
      return {
        format: "WebP",
        width: littleEndian16(bytes, 26) & 0x3fff,
        height: littleEndian16(bytes, 28) & 0x3fff
      };
    }
  }

  if (bytes.length >= 10 && bytes[0] === 0xff && bytes[1] === 0xd8) {
    let offset = 2;
    while (offset + 3 < bytes.length) {
      if (bytes[offset++] !== 0xff) continue;
      while (offset < bytes.length && bytes[offset] === 0xff) offset++;
      if (offset >= bytes.length) break;
      const marker = bytes[offset++];
      if (marker === 0xda || marker === 0xd9) break;
      if (marker === 0x01 || marker === 0xd8 ||
          (marker >= 0xd0 && marker <= 0xd7)) continue;
      if (offset + 1 >= bytes.length) break;
      const length = bigEndian16(bytes, offset);
      if (length < 2 || offset + length > bytes.length) break;
      if ((marker >= 0xc0 && marker <= 0xc3) ||
          (marker >= 0xc5 && marker <= 0xc7) ||
          (marker >= 0xc9 && marker <= 0xcb) ||
          (marker >= 0xcd && marker <= 0xcf)) {
        if (length < 7) break;
        return {
          format: "JPEG",
          width: bigEndian16(bytes, offset + 5),
          height: bigEndian16(bytes, offset + 3)
        };
      }
      offset += length;
    }
  }

  return null;
}

const bytes = responseBytes();
const image = bytes ? imageSize(bytes) : null;

if (image) {
  console.log(`[DKKJ-AD] ${image.format} ${image.width}x${image.height}`);
}

if (image && image.width === AD_WIDTH && image.height === AD_HEIGHT) {
  console.log("[DKKJ-AD] Splash image blocked (204)");
  $done({ status: "HTTP/1.1 204 No Content", headers: {}, body: "" });
} else {
  $done({});
}
