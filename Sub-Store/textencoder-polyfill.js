(function(global){
  if (typeof global.TextEncoder !== 'undefined' && typeof global.TextDecoder !== 'undefined') return;

  function _toUint8Array(str){
    var encoded = unescape(encodeURIComponent(String(str)));
    var arr = new Uint8Array(encoded.length);
    for (var i = 0; i < encoded.length; i++) arr[i] = encoded.charCodeAt(i);
    return arr;
  }

  function _fromUint8Array(arr){
    var s = '';
    for (var i = 0; i < arr.length; i++) s += String.fromCharCode(arr[i]);
    try { return decodeURIComponent(escape(s)); } catch (e) { return s; }
  }

  function TextEncoderPoly() {}
  TextEncoderPoly.prototype.encode = function(str){ return _toUint8Array(str); };

  function TextDecoderPoly() {}
  TextDecoderPoly.prototype.decode = function(buf){
    if (buf instanceof ArrayBuffer) buf = new Uint8Array(buf);
    return _fromUint8Array(buf);
  };

  global.TextEncoder = TextEncoderPoly;
  global.TextDecoder = TextDecoderPoly;
})(typeof globalThis !== 'undefined' ? globalThis : (typeof global !== 'undefined' ? global : this));
