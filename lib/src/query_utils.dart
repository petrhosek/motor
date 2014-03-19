library motor.query_utils;

import 'dart:uri';

/**
 * Parses a querystring.
 */
Map parse(String query) {
  final search = new RegExp('([^&=]+)=?([^&]*)');
  
  decode(String s) {
    return decodeUriComponent(s.replaceAll('+', ' '));
  }
  
  var components = {};
  search.allMatches(query).forEach((match) {
    components[decode(match.group(1))] = decode(match.group(2));
  });
  return components;
}

/**
 * Compiles a querystring.
 */
String stringify(Map query) {
  encode(String s) {
    return encodeUriComponent(s.replaceAll(' ', '+'));
  }
  
  var components = [];
  query.forEach((key, value) {
    components.add('${encode(key)}=${encode(value)}');    
  });
  return components.join('&');
}