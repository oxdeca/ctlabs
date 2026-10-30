/**
 * markdown_emojis.js - Markdown Emoji Shortcodes Support for CTLABS Walkthrough
 * Provides mapping from :shortcode: to Unicode emoji and code-safe text replacement.
 */

(function(root) {
  'use strict';

  // Comprehensive GitHub/Markdown emoji dictionary
  const MD_EMOJI_MAP = {
    // Status, Alerts & Checks
    'warning': '⚠️',
    'white_check_mark': '✅',
    'heavy_check_mark': '✔️',
    'check_mark': '✔️',
    'x': '❌',
    'cross_mark': '❌',
    'negative_squared_cross_mark': '❎',
    'bangbang': '‼️',
    'interrobang': '⁉️',
    'question': '❓',
    'grey_question': '❔',
    'exclamation': '❗',
    'grey_exclamation': '❕',
    'stop_sign': '🛑',
    'octagonal_sign': '🛑',
    'no_entry': '⛔',
    'no_entry_sign': '🚫',
    'radioactive': '☢️',
    'biohazard': '☣️',
    'sos': '🆘',
    'information_source': 'ℹ️',
    'info': 'ℹ️',
    'bulb': '💡',
    'bell': '🔔',
    'no_bell': '🔕',
    'traffic_light': '🚦',
    'vertical_traffic_light': '🚥',
    'construction': '🚧',
    'lock': '🔒',
    'unlock': '🔓',
    'closed_lock_with_key': '🔐',
    'lock_with_ink_pen': '🔏',
    'key': '🔑',
    'old_key': '🗝️',
    'shield': '🛡️',

    // Tech, Coding & DevOps
    'rocket': '🚀',
    'bug': '🐛',
    'gear': '⚙️',
    'gears': '⚙️',
    'wrench': '🔧',
    'hammer': '🔨',
    'hammer_and_wrench': '🛠️',
    'tools': '🛠️',
    'nut_and_bolt': '🔩',
    'screwdriver': '🪛',
    'package': '📦',
    'link': '🔗',
    'chains': '⛓️',
    'fire': '🔥',
    'zap': '⚡',
    'sparkles': '✨',
    'boom': '💥',
    'collision': '💥',
    'computer': '💻',
    'desktop_computer': '🖥️',
    'keyboard': '⌨️',
    'terminal': '💻',
    'server': '🖥️',
    'floppy_disk': '💾',
    'cd': '💿',
    'dvd': '📀',
    'robot': '🤖',
    'satellite': '📡',
    'cloud': '☁️',
    'globe_with_meridians': '🌐',
    'network': '🌐',
    'mag': '🔍',
    'mag_right': '🔎',
    'telescope': '🔭',
    'microscope': '🔬',
    'chart_with_upwards_trend': '📈',
    'chart_with_downwards_trend': '📉',
    'bar_chart': '📊',
    'memo': '📝',
    'pencil': '📝',
    'pencil2': '✏️',
    'clipboard': '📋',
    'page_facing_up': '📄',
    'page_with_curl': '📃',
    'scroll': '📜',
    'file_folder': '📁',
    'open_file_folder': '📂',
    'card_index': '📇',
    'paperclip': '📎',
    'paperclips': '🖇️',
    'pushpin': '📌',
    'round_pushpin': '📍',
    'inbox_tray': '📥',
    'outbox_tray': '📤',
    'envelope': '✉️',
    'email': '✉️',
    'incoming_envelope': '📨',
    'calendar': '📅',
    'clock': '🕒',
    'stopwatch': '⏱️',
    'timer_clock': '⏲️',
    'hourglass': '⌛',
    'hourglass_flowing_sand': '⏳',
    'battery': '🔋',
    'electric_plug': '🔌',
    'dna': '🧬',
    'test_tube': '🧪',
    'petri_dish': '🧫',
    'database': '🗄️',
    'file_cabinet': '🗄️',
    'books': '📚',
    'book': '📖',
    'bookmark': '🔖',

    // Reactions, People & Gestures
    'thumbsup': '👍',
    '+1': '👍',
    'thumbsdown': '👎',
    '-1': '👎',
    'clap': '👏',
    'wave': '👋',
    'ok_hand': '👌',
    'pray': '🙏',
    'muscle': '💪',
    'eyes': '👀',
    'eye': '👁️',
    'brain': '🧠',
    'smile': '😄',
    'smiley': '😃',
    'grinning': '😀',
    'grin': '😁',
    'joy': '😂',
    'rofl': '🤣',
    'sweat_smile': '😅',
    'wink': '😉',
    'blush': '😊',
    'innocent': '😇',
    'heart_eyes': '😍',
    'sunglasses': '😎',
    'nerd_face': '🤓',
    'thinking': '🤔',
    'neutral_face': '😐',
    'expressionless': '😑',
    'unamused': '😒',
    'confused': '😕',
    'pensive': '😔',
    'upside_down_face': '🙃',
    'money_mouth_face': '🤑',
    'astonished': '😲',
    'cry': '😢',
    'sob': '😭',
    'scream': '😱',
    'angry': '😠',
    'rage': '😡',
    'mask': '😷',
    'shrug': '🤷',
    'facepalm': '🤦',
    'skull': '💀',
    'ghost': '👻',
    'alien': '👽',
    'poop': '💩',
    'man_technologist': '👨‍💻',
    'woman_technologist': '👩‍💻',

    // Symbols, Marks & Indicators
    'checkered_flag': '🏁',
    'triangular_flag_on_post': '🚩',
    'white_flag': '🏳️',
    'black_flag': '🏴',
    'star': '⭐',
    'star2': '🌟',
    'heart': '❤️',
    'orange_heart': '🧡',
    'yellow_heart': '💛',
    'green_heart': '💚',
    'blue_heart': '💙',
    'purple_heart': '💜',
    'black_heart': '🖤',
    'white_heart': '🤍',
    'broken_heart': '💔',
    'sparkling_heart': '💖',
    'tada': '🎉',
    'party_popper': '🎉',
    'confetti_ball': '🎊',
    'trophy': '🏆',
    'medal': '🏅',
    'first_place_medal': '🥇',
    'second_place_medal': '🥈',
    'third_place_medal': '🥉',
    'target': '🎯',
    'gem': '💎',
    '100': '💯',
    'coffee': '☕',
    'tea': '🍵',
    'beer': '🍺',
    'beers': '🍻',
    'pizza': '🍕',
    'cake': '🍰',
    'apple': '🍎',
    'green_circle': '🟢',
    'red_circle': '🔴',
    'blue_circle': '🔵',
    'large_blue_circle': '🔵',
    'yellow_circle': '🟡',
    'orange_circle': '🟠',
    'purple_circle': '🟣',
    'black_circle': '⚫',
    'white_circle': '⚪',
    'large_blue_diamond': '🔷',
    'large_orange_diamond': '🔶',
    'small_blue_diamond': '🔹',
    'small_orange_diamond': '🔸',
    'white_large_square': '⬜',
    'black_large_square': '⬛',
    'arrow_right': '➡️',
    'arrow_left': '⬅️',
    'arrow_up': '⬆️',
    'arrow_down': '⬇️',
    'arrow_upper_right': '↗️',
    'arrow_lower_right': '↘️',
    'arrow_lower_left': '↙️',
    'arrow_upper_left': '↖️',
    'arrows_counterclockwise': '🔄',
    'arrows_clockwise': '🔃',
    'recycle': '♻️',
    'point_right': '👉',
    'point_left': '👈',
    'point_up': '👆',
    'point_down': '👇',
    'heavy_plus_sign': '➕',
    'heavy_minus_sign': '➖',
    'heavy_multiplication_x': '✖️',
    'heavy_division_sign': '➗',
    'hash': '#️⃣',
    'asterisk': '*️⃣',
    'zero': '0️⃣',
    'one': '1️⃣',
    'two': '2️⃣',
    'three': '3️⃣',
    'four': '4️⃣',
    'five': '5️⃣',
    'six': '6️⃣',
    'seven': '7️⃣',
    'eight': '8️⃣',
    'nine': '9️⃣',
    'keycap_ten': '🔟',
    '1234': '🔢',
    'play': '▶️',
    'pause': '⏸️',
    'play_pause': '⏯️',
    'stop_button': '⏹️',
    'record_button': '⏺️',
    'fast_forward': '⏩',
    'rewind': '⏪',
    'ok': '🆗',
    'up': '🆙',
    'cool': '🆒',
    'new': '🆕',
    'free': '🆓',
    'copyright': '©',
    'registered': '®',
    'tm': '™',
    'trademark': '™',
    'seedling': '🌱',
    'evergreen_tree': '🌲',
    'palm_tree': '🌴',
    'earth_americas': '🌎',
    'sun_with_face': '🌞',
    'crescent_moon': '🌙',
    'rainbow': '🌈',
    'snowflake': '❄️',
    'car': '🚗',
    'airplane': '✈️',
    'boat': '⛵'
  };

  // Structured categories for the UI Emoji picker
  const MD_EMOJI_CATEGORIES = [
    {
      id: 'all',
      name: 'Popular & Common',
      icon: '⚡',
      items: [
        'rocket', 'warning', 'white_check_mark', 'x', 'bulb', 'fire', 'memo', 'tada',
        'gear', 'wrench', 'tools', 'package', 'lock', 'key', 'link', 'shield',
        'star', 'heart', 'thumbsup', 'thumbsdown', 'eyes', 'robot', 'bug', 'zap',
        'sparkles', 'boom', 'computer', 'server', 'globe_with_meridians', 'mag',
        'clipboard', 'calendar', 'clock', 'stop_sign', 'bell', 'question', 'exclamation',
        'traffic_light', 'construction', '100', 'trophy', 'target', 'coffee'
      ]
    },
    {
      id: 'status',
      name: 'Status & Alerts',
      icon: '⚠️',
      items: [
        'warning', 'white_check_mark', 'heavy_check_mark', 'x', 'cross_mark', 'negative_squared_cross_mark',
        'stop_sign', 'no_entry', 'no_entry_sign', 'question', 'grey_question', 'exclamation',
        'grey_exclamation', 'bangbang', 'interrobang', 'info', 'information_source', 'sos',
        'bulb', 'bell', 'no_bell', 'traffic_light', 'vertical_traffic_light', 'construction',
        'radioactive', 'biohazard', 'lock', 'unlock', 'closed_lock_with_key', 'key', 'old_key', 'shield'
      ]
    },
    {
      id: 'tech',
      name: 'Tech & DevOps',
      icon: '🚀',
      items: [
        'rocket', 'computer', 'desktop_computer', 'keyboard', 'terminal', 'server',
        'database', 'robot', 'package', 'gear', 'wrench', 'hammer', 'tools',
        'nut_and_bolt', 'screwdriver', 'bug', 'fire', 'zap', 'sparkles', 'boom',
        'cloud', 'globe_with_meridians', 'satellite', 'mag', 'telescope', 'microscope',
        'floppy_disk', 'cd', 'dvd', 'battery', 'electric_plug', 'dna', 'test_tube',
        'chart_with_upwards_trend', 'chart_with_downwards_trend', 'bar_chart', 'memo', 'clipboard',
        'page_facing_up', 'file_folder', 'paperclip', 'calendar', 'clock', 'stopwatch', 'hourglass'
      ]
    },
    {
      id: 'people',
      name: 'People & Reactions',
      icon: '👍',
      items: [
        'thumbsup', 'thumbsdown', 'clap', 'wave', 'ok_hand', 'pray', 'muscle', 'eyes',
        'brain', 'smile', 'smiley', 'grinning', 'grin', 'joy', 'rofl', 'sweat_smile',
        'wink', 'blush', 'innocent', 'heart_eyes', 'sunglasses', 'nerd_face', 'thinking',
        'neutral_face', 'expressionless', 'unamused', 'confused', 'pensive', 'upside_down_face',
        'astonished', 'cry', 'sob', 'scream', 'angry', 'rage', 'mask', 'shrug', 'facepalm',
        'skull', 'ghost', 'alien', 'poop', 'man_technologist', 'woman_technologist'
      ]
    },
    {
      id: 'symbols',
      name: 'Symbols & Objects',
      icon: '⭐',
      items: [
        'star', 'star2', 'heart', 'broken_heart', 'sparkling_heart', 'tada', 'confetti_ball',
        'trophy', 'medal', 'first_place_medal', 'second_place_medal', 'third_place_medal', 'target',
        'gem', '100', 'checkered_flag', 'triangular_flag_on_post', 'white_flag', 'black_flag',
        'arrow_right', 'arrow_left', 'arrow_up', 'arrow_down', 'arrows_counterclockwise', 'recycle',
        'point_right', 'point_left', 'point_up', 'point_down', 'green_circle', 'red_circle',
        'blue_circle', 'yellow_circle', 'orange_circle', 'purple_circle', 'black_circle', 'white_circle',
        'large_blue_diamond', 'large_orange_diamond', 'heavy_plus_sign', 'heavy_minus_sign',
        'hash', 'asterisk', 'play', 'pause', 'stop_button', 'coffee', 'tea', 'beer', 'pizza'
      ]
    }
  ];

  /**
   * Code-safe emoji shortcode replacer.
   * Protects fenced code blocks, inline code, HTML tags, and URLs before replacing :code:.
   */
  function replaceEmojiShortcodes(text) {
    if (!text || typeof text !== 'string') return text;

    const codeTokens = [];
    const tokenPrefix = '@@EMOJI_VAULT_' + Math.random().toString(36).slice(2) + '_';

    // 1. Fenced code blocks (``` ... ``` or ~~~ ... ~~~)
    let processed = text.replace(/(```[\s\S]*?```|~~~[\s\S]*?~~~)/g, function(match) {
      const idx = codeTokens.length;
      codeTokens.push(match);
      return tokenPrefix + idx + '@@';
    });

    // 2. Inline code (` ... `)
    processed = processed.replace(/(`[^`\n]+`)/g, function(match) {
      const idx = codeTokens.length;
      codeTokens.push(match);
      return tokenPrefix + idx + '@@';
    });

    // 3. HTML tags (< ... >)
    processed = processed.replace(/(<[^>]+>)/g, function(match) {
      const idx = codeTokens.length;
      codeTokens.push(match);
      return tokenPrefix + idx + '@@';
    });

    // 4. URLs (http:// or https://)
    processed = processed.replace(/(https?:\/\/[^\s\)<>"]+)/g, function(match) {
      const idx = codeTokens.length;
      codeTokens.push(match);
      return tokenPrefix + idx + '@@';
    });

    // 5. Replace :shortcode: if in MD_EMOJI_MAP
    processed = processed.replace(/:([a-zA-Z0-9_+-]+):/g, function(match, code) {
      const lower = code.toLowerCase();
      if (Object.prototype.hasOwnProperty.call(MD_EMOJI_MAP, lower)) {
        return MD_EMOJI_MAP[lower];
      }
      if (Object.prototype.hasOwnProperty.call(MD_EMOJI_MAP, code)) {
        return MD_EMOJI_MAP[code];
      }
      return match;
    });

    // 6. Restore stashed tokens in reverse order
    for (let i = codeTokens.length - 1; i >= 0; i--) {
      const token = tokenPrefix + i + '@@';
      processed = processed.split(token).join(codeTokens[i]);
    }

    return processed;
  }

  // Export to global scope
  root.MD_EMOJI_MAP = MD_EMOJI_MAP;
  root.MD_EMOJI_CATEGORIES = MD_EMOJI_CATEGORIES;
  root.replaceEmojiShortcodes = replaceEmojiShortcodes;

})(typeof window !== 'undefined' ? window : this);
