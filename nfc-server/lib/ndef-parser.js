/**
 * NDEF parsing utilities
 */

/**
 * Parse NDEF URL from raw NDEF record data
 * @param {Buffer} data - Raw NDEF record data (format: [flags][typeLength][payloadLength][type][payload])
 * @returns {string|null} - Parsed URL or null if not a URL record
 */
export function parseNDEFUrl(data) {
  try {
    if (!data || data.length === 0) {
      return null;
    }

    if (data.length < 5) {
      console.error(`parseNDEFUrl: NDEF data too short: ${data.length} bytes`);
      return null;
    }

    const recordHeader = data[0];
    const typeLength = data[1];
    const hasIdLength = (recordHeader & 0x08) !== 0; // IL flag (bit 3)

    // Payload length can be 1 byte (short record, SR=1) or 3 bytes (long record, SR=0)
    let payloadLength;
    let idLength = 0;
    let typeOffset;

    if (recordHeader & 0x10) {
      // Short record (SR=1): 1-byte payload length
      payloadLength = data[2];
      typeOffset = 3;
      if (hasIdLength) {
        idLength = data[3];
        typeOffset = 4;
      }
    } else {
      // Long record (SR=0): 3-byte payload length
      payloadLength = (data[2] << 16) | (data[3] << 8) | data[4];
      typeOffset = 5;
      if (hasIdLength) {
        idLength = data[5];
        typeOffset = 6;
      }
    }

    if (typeLength !== 1) {
      return null; // Not a URL record
    }

    const type = data[typeOffset];
    if (type !== 0x55) {
      return null; // Not a URL record (U = 0x55)
    }

    const payloadOffset = typeOffset + typeLength + idLength;
    if (payloadOffset + payloadLength > data.length) {
      console.error(
        `parseNDEFUrl: Payload out of bounds (offset=${payloadOffset}, length=${data.length}, payloadLength=${payloadLength})`,
      );
      return null;
    }

    const payload = data.slice(payloadOffset, payloadOffset + payloadLength);
    if (payload.length === 0) {
      console.error("parseNDEFUrl: Empty payload");
      return null;
    }

    // URL prefix codes: https://www.ndef.org/resources/url-prefixes
    const prefixes = {
      0x00: "",
      0x01: "http://www.",
      0x02: "https://www.",
      0x03: "http://",
      0x04: "https://",
    };

    return (prefixes[payload[0]] || "") + payload.slice(1).toString("utf-8");
  } catch (error) {
    console.error(
      "NDEF parse error:",
      error,
      "Data hex:",
      data?.toString("hex")?.substring(0, 100),
    );
    return null;
  }
}

/**
 * Create NDEF URL record (raw format, no TLV wrapper)
 * For Type 4 tags accessed via APDU, the raw NDEF record is written directly
 * @param {string} url - URL to encode
 * @returns {Buffer} - Raw NDEF record as Buffer (format: [flags][typeLength][payloadLength][type][payload])
 */
export function createNDEFUrlRecord(url) {
  // Determine URL prefix
  let prefix = 0x04; // https://
  let urlWithoutPrefix = url;

  if (url.startsWith("https://www.")) {
    prefix = 0x02;
    urlWithoutPrefix = url.substring(12);
  } else if (url.startsWith("http://www.")) {
    prefix = 0x01;
    urlWithoutPrefix = url.substring(11);
  } else if (url.startsWith("https://")) {
    prefix = 0x04;
    urlWithoutPrefix = url.substring(8);
  } else if (url.startsWith("http://")) {
    prefix = 0x03;
    urlWithoutPrefix = url.substring(7);
  }

  const urlBytes = Buffer.from(urlWithoutPrefix, "utf-8");

  // NDEF Record Header
  // MB=1, ME=1, CF=0, SR=1, IL=0, TNF=0x01 (Well Known Type)
  const recordHeader = 0xd1;
  const typeLength = 0x01;
  const payloadLength = 1 + urlBytes.length;
  const type = 0x55; // "U"

  return Buffer.concat([
    Buffer.from([recordHeader]),
    Buffer.from([typeLength]),
    Buffer.from([payloadLength]),
    Buffer.from([type]),
    Buffer.from([prefix]),
    urlBytes,
  ]);
}
