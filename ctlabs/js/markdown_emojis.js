/**
 * markdown_emojis.js - Full GitHub & Markdown Emoji Support for CTLABS
 * Supports all 1,936 GitHub emojis (including :octocat:, :shipit:, :copilot:, :+1:, etc.)
 * Provides code-safe shortcode replacement and rich UI picker dictionary.
 */

(function(root) {
  'use strict';

  const GITHUB_EMOJI_LIST = [
  {
    "code": "firewall",
    "char": "🛡️",
    "name": "Firewall / WAF / Shield",
    "cat": "tech"
  },
  {
    "code": "database",
    "char": "🗄️",
    "name": "Database / DB / Storage",
    "cat": "tech"
  },
  {
    "code": "server",
    "char": "🖥️",
    "name": "Server / Host / Machine",
    "cat": "tech"
  },
  {
    "code": "k8s",
    "char": "☸️",
    "name": "Kubernetes / K8s / Helm",
    "cat": "tech"
  },
  {
    "code": "docker",
    "char": "🐳",
    "name": "Docker / Container",
    "cat": "tech"
  },
  {
    "code": "octocat",
    "img": "https://github.githubassets.com/images/icons/emoji/octocat.png?v8",
    "name": "octocat",
    "cat": "github"
  },
  {
    "code": "shipit",
    "img": "https://github.githubassets.com/images/icons/emoji/shipit.png?v8",
    "name": "shipit",
    "cat": "github"
  },
  {
    "code": "copilot",
    "img": "https://github.githubassets.com/images/icons/emoji/copilot.png?v8",
    "name": "copilot",
    "cat": "github"
  },
  {
    "code": "dependabot",
    "img": "https://github.githubassets.com/images/icons/emoji/dependabot.png?v8",
    "name": "dependabot",
    "cat": "github"
  },
  {
    "code": "bowtie",
    "img": "https://github.githubassets.com/images/icons/emoji/bowtie.png?v8",
    "name": "bowtie",
    "cat": "github"
  },
  {
    "code": "feelsgood",
    "img": "https://github.githubassets.com/images/icons/emoji/feelsgood.png?v8",
    "name": "feelsgood",
    "cat": "github"
  },
  {
    "code": "finnadie",
    "img": "https://github.githubassets.com/images/icons/emoji/finnadie.png?v8",
    "name": "finnadie",
    "cat": "github"
  },
  {
    "code": "fishsticks",
    "img": "https://github.githubassets.com/images/icons/emoji/fishsticks.png?v8",
    "name": "fishsticks",
    "cat": "github"
  },
  {
    "code": "goberserk",
    "img": "https://github.githubassets.com/images/icons/emoji/goberserk.png?v8",
    "name": "goberserk",
    "cat": "github"
  },
  {
    "code": "godmode",
    "img": "https://github.githubassets.com/images/icons/emoji/godmode.png?v8",
    "name": "godmode",
    "cat": "github"
  },
  {
    "code": "hurtrealbad",
    "img": "https://github.githubassets.com/images/icons/emoji/hurtrealbad.png?v8",
    "name": "hurtrealbad",
    "cat": "github"
  },
  {
    "code": "neckbeard",
    "img": "https://github.githubassets.com/images/icons/emoji/neckbeard.png?v8",
    "name": "neckbeard",
    "cat": "github"
  },
  {
    "code": "rage1",
    "img": "https://github.githubassets.com/images/icons/emoji/rage1.png?v8",
    "name": "rage1",
    "cat": "github"
  },
  {
    "code": "rage2",
    "img": "https://github.githubassets.com/images/icons/emoji/rage2.png?v8",
    "name": "rage2",
    "cat": "github"
  },
  {
    "code": "rage3",
    "img": "https://github.githubassets.com/images/icons/emoji/rage3.png?v8",
    "name": "rage3",
    "cat": "github"
  },
  {
    "code": "rage4",
    "img": "https://github.githubassets.com/images/icons/emoji/rage4.png?v8",
    "name": "rage4",
    "cat": "github"
  },
  {
    "code": "suspect",
    "img": "https://github.githubassets.com/images/icons/emoji/suspect.png?v8",
    "name": "suspect",
    "cat": "github"
  },
  {
    "code": "trollface",
    "img": "https://github.githubassets.com/images/icons/emoji/trollface.png?v8",
    "name": "trollface",
    "cat": "github"
  },
  {
    "code": "atom",
    "img": "https://github.githubassets.com/images/icons/emoji/atom.png?v8",
    "name": "atom",
    "cat": "github"
  },
  {
    "code": "electron",
    "img": "https://github.githubassets.com/images/icons/emoji/electron.png?v8",
    "name": "electron",
    "cat": "github"
  },
  {
    "code": "basecamp",
    "img": "https://github.githubassets.com/images/icons/emoji/basecamp.png?v8",
    "name": "basecamp",
    "cat": "github"
  },
  {
    "code": "basecampy",
    "img": "https://github.githubassets.com/images/icons/emoji/basecampy.png?v8",
    "name": "basecampy",
    "cat": "github"
  },
  {
    "code": "accessibility",
    "img": "https://github.githubassets.com/images/icons/emoji/accessibility.png?v8",
    "name": "accessibility",
    "cat": "github"
  },
  {
    "code": "+1",
    "char": "👍",
    "name": "Thumbs up",
    "cat": "github"
  },
  {
    "code": "-1",
    "char": "👎",
    "name": "Thumbs down",
    "cat": "github"
  },
  {
    "code": "tada",
    "char": "🎉",
    "name": "Party popper",
    "cat": "github"
  },
  {
    "code": "rocket",
    "char": "🚀",
    "name": "Rocket",
    "cat": "github"
  },
  {
    "code": "bug",
    "char": "🐛",
    "name": "Bug",
    "cat": "github"
  },
  {
    "code": "sparkles",
    "char": "✨",
    "name": "Sparkles",
    "cat": "github"
  },
  {
    "code": "fire",
    "char": "🔥",
    "name": "Fire",
    "cat": "github"
  },
  {
    "code": "eyes",
    "char": "👀",
    "name": "Eyes",
    "cat": "github"
  },
  {
    "code": "100",
    "char": "💯",
    "name": "Hundred points",
    "cat": "github"
  },
  {
    "code": "memo",
    "char": "📝",
    "name": "Memo",
    "cat": "github"
  },
  {
    "code": "heavy_check_mark",
    "char": "✔",
    "name": "Check mark",
    "cat": "github"
  },
  {
    "code": "x",
    "char": "❌",
    "name": "Cross mark",
    "cat": "github"
  },
  {
    "code": "warning",
    "char": "⚠",
    "name": "Warning",
    "cat": "github"
  },
  {
    "code": "lock",
    "char": "🔒",
    "name": "Locked",
    "cat": "github"
  },
  {
    "code": "key",
    "char": "🔑",
    "name": "Key",
    "cat": "github"
  },
  {
    "code": "shield",
    "char": "🛡",
    "name": "Shield",
    "cat": "github"
  },
  {
    "code": "computer",
    "char": "💻",
    "name": "Laptop",
    "cat": "github"
  },
  {
    "code": "package",
    "char": "📦",
    "name": "Package",
    "cat": "github"
  },
  {
    "code": "gear",
    "char": "⚙",
    "name": "Gear",
    "cat": "github"
  },
  {
    "code": "wrench",
    "char": "🔧",
    "name": "Wrench",
    "cat": "github"
  },
  {
    "code": "robot",
    "char": "🤖",
    "name": "Robot",
    "cat": "github"
  },
  {
    "code": "heart",
    "char": "❤",
    "name": "Red heart",
    "cat": "github"
  },
  {
    "code": "thinking",
    "char": "🤔",
    "name": "Thinking face",
    "cat": "github"
  },
  {
    "code": "clap",
    "char": "👏",
    "name": "Clapping hands",
    "cat": "github"
  },
  {
    "code": "wave",
    "char": "👋",
    "name": "Waving hand",
    "cat": "github"
  },
  {
    "code": "pray",
    "char": "🙏",
    "name": "Folded hands",
    "cat": "github"
  },
  {
    "code": "muscle",
    "char": "💪",
    "name": "Flexed biceps",
    "cat": "github"
  },
  {
    "code": "smile",
    "char": "😄",
    "name": "Grinning face with smiling eyes",
    "cat": "github"
  },
  {
    "code": "grin",
    "char": "😁",
    "name": "Beaming face with smiling eyes",
    "cat": "github"
  },
  {
    "code": "joy",
    "char": "😂",
    "name": "Face with tears of joy",
    "cat": "github"
  },
  {
    "code": "sweat_smile",
    "char": "😅",
    "name": "Grinning face with sweat",
    "cat": "github"
  },
  {
    "code": "sunglasses",
    "char": "😎",
    "name": "Smiling face with sunglasses",
    "cat": "github"
  },
  {
    "code": "nerd_face",
    "char": "🤓",
    "name": "Nerd face",
    "cat": "github"
  },
  {
    "code": "facepalm",
    "char": "🤦",
    "name": "Person facepalming",
    "cat": "github"
  },
  {
    "code": "shrug",
    "char": "🤷",
    "name": "Person shrugging",
    "cat": "github"
  },
  {
    "code": "exploding_head",
    "char": "🤯",
    "name": "Exploding head",
    "cat": "github"
  },
  {
    "code": "checkered_flag",
    "char": "🏁",
    "name": "Chequered flag",
    "cat": "github"
  },
  {
    "code": "speech_balloon",
    "char": "💬",
    "name": "Speech balloon",
    "cat": "github"
  },
  {
    "code": "1234",
    "char": "🔢",
    "name": "Input numbers",
    "cat": "symbols"
  },
  {
    "code": "1st_place_medal",
    "char": "🥇",
    "name": "1st place medal",
    "cat": "symbols"
  },
  {
    "code": "2nd_place_medal",
    "char": "🥈",
    "name": "2nd place medal",
    "cat": "symbols"
  },
  {
    "code": "3rd_place_medal",
    "char": "🥉",
    "name": "3rd place medal",
    "cat": "symbols"
  },
  {
    "code": "8ball",
    "char": "🎱",
    "name": "Pool 8 ball",
    "cat": "symbols"
  },
  {
    "code": "a",
    "char": "🅰",
    "name": "A button (blood type)",
    "cat": "symbols"
  },
  {
    "code": "ab",
    "char": "🆎",
    "name": "AB button (blood type)",
    "cat": "symbols"
  },
  {
    "code": "abacus",
    "char": "🧮",
    "name": "Abacus",
    "cat": "tech"
  },
  {
    "code": "abc",
    "char": "🔤",
    "name": "Input latin letters",
    "cat": "symbols"
  },
  {
    "code": "abcd",
    "char": "🔡",
    "name": "Input latin lowercase",
    "cat": "symbols"
  },
  {
    "code": "accept",
    "char": "🉑",
    "name": "Japanese “acceptable” button",
    "cat": "symbols"
  },
  {
    "code": "accordion",
    "char": "🪗",
    "name": "Accordion",
    "cat": "tech"
  },
  {
    "code": "adhesive_bandage",
    "char": "🩹",
    "name": "Adhesive bandage",
    "cat": "tech"
  },
  {
    "code": "adult",
    "char": "🧑",
    "name": "Person",
    "cat": "people"
  },
  {
    "code": "aerial_tramway",
    "char": "🚡",
    "name": "Aerial tramway",
    "cat": "symbols"
  },
  {
    "code": "afghanistan",
    "char": "🇦🇫",
    "name": "Flag: Afghanistan",
    "cat": "symbols"
  },
  {
    "code": "airplane",
    "char": "✈",
    "name": "Airplane",
    "cat": "symbols"
  },
  {
    "code": "aland_islands",
    "char": "🇦🇽",
    "name": "Flag: Åland Islands",
    "cat": "symbols"
  },
  {
    "code": "alarm_clock",
    "char": "⏰",
    "name": "Alarm clock",
    "cat": "status"
  },
  {
    "code": "albania",
    "char": "🇦🇱",
    "name": "Flag: Albania",
    "cat": "symbols"
  },
  {
    "code": "alembic",
    "char": "⚗",
    "name": "Alembic",
    "cat": "tech"
  },
  {
    "code": "algeria",
    "char": "🇩🇿",
    "name": "Flag: Algeria",
    "cat": "symbols"
  },
  {
    "code": "alien",
    "char": "👽",
    "name": "Alien",
    "cat": "people"
  },
  {
    "code": "ambulance",
    "char": "🚑",
    "name": "Ambulance",
    "cat": "symbols"
  },
  {
    "code": "american_samoa",
    "char": "🇦🇸",
    "name": "Flag: American Samoa",
    "cat": "symbols"
  },
  {
    "code": "amphora",
    "char": "🏺",
    "name": "Amphora",
    "cat": "symbols"
  },
  {
    "code": "anatomical_heart",
    "char": "🫀",
    "name": "Anatomical heart",
    "cat": "people"
  },
  {
    "code": "anchor",
    "char": "⚓",
    "name": "Anchor",
    "cat": "symbols"
  },
  {
    "code": "andorra",
    "char": "🇦🇩",
    "name": "Flag: Andorra",
    "cat": "symbols"
  },
  {
    "code": "angel",
    "char": "👼",
    "name": "Baby angel",
    "cat": "people"
  },
  {
    "code": "anger",
    "char": "💢",
    "name": "Anger symbol",
    "cat": "people"
  },
  {
    "code": "angola",
    "char": "🇦🇴",
    "name": "Flag: Angola",
    "cat": "symbols"
  },
  {
    "code": "angry",
    "char": "😠",
    "name": "Angry face",
    "cat": "people"
  },
  {
    "code": "anguilla",
    "char": "🇦🇮",
    "name": "Flag: Anguilla",
    "cat": "symbols"
  },
  {
    "code": "anguished",
    "char": "😧",
    "name": "Anguished face",
    "cat": "people"
  },
  {
    "code": "ant",
    "char": "🐜",
    "name": "Ant",
    "cat": "tech"
  },
  {
    "code": "antarctica",
    "char": "🇦🇶",
    "name": "Flag: Antarctica",
    "cat": "symbols"
  },
  {
    "code": "antigua_barbuda",
    "char": "🇦🇬",
    "name": "Flag: Antigua & Barbuda",
    "cat": "symbols"
  },
  {
    "code": "apple",
    "char": "🍎",
    "name": "Red apple",
    "cat": "symbols"
  },
  {
    "code": "aquarius",
    "char": "♒",
    "name": "Aquarius",
    "cat": "symbols"
  },
  {
    "code": "argentina",
    "char": "🇦🇷",
    "name": "Flag: Argentina",
    "cat": "symbols"
  },
  {
    "code": "aries",
    "char": "♈",
    "name": "Aries",
    "cat": "symbols"
  },
  {
    "code": "armenia",
    "char": "🇦🇲",
    "name": "Flag: Armenia",
    "cat": "symbols"
  },
  {
    "code": "arrow_backward",
    "char": "◀",
    "name": "Reverse button",
    "cat": "symbols"
  },
  {
    "code": "arrow_double_down",
    "char": "⏬",
    "name": "Fast down button",
    "cat": "symbols"
  },
  {
    "code": "arrow_double_up",
    "char": "⏫",
    "name": "Fast up button",
    "cat": "symbols"
  },
  {
    "code": "arrow_down",
    "char": "⬇",
    "name": "Down arrow",
    "cat": "symbols"
  },
  {
    "code": "arrow_down_small",
    "char": "🔽",
    "name": "Downwards button",
    "cat": "symbols"
  },
  {
    "code": "arrow_forward",
    "char": "▶",
    "name": "Play button",
    "cat": "symbols"
  },
  {
    "code": "arrow_heading_down",
    "char": "⤵",
    "name": "Right arrow curving down",
    "cat": "symbols"
  },
  {
    "code": "arrow_heading_up",
    "char": "⤴",
    "name": "Right arrow curving up",
    "cat": "symbols"
  },
  {
    "code": "arrow_left",
    "char": "⬅",
    "name": "Left arrow",
    "cat": "symbols"
  },
  {
    "code": "arrow_lower_left",
    "char": "↙",
    "name": "Down-left arrow",
    "cat": "symbols"
  },
  {
    "code": "arrow_lower_right",
    "char": "↘",
    "name": "Down-right arrow",
    "cat": "symbols"
  },
  {
    "code": "arrow_right",
    "char": "➡",
    "name": "Right arrow",
    "cat": "symbols"
  },
  {
    "code": "arrow_right_hook",
    "char": "↪",
    "name": "Left arrow curving right",
    "cat": "symbols"
  },
  {
    "code": "arrow_up",
    "char": "⬆",
    "name": "Up arrow",
    "cat": "symbols"
  },
  {
    "code": "arrow_up_down",
    "char": "↕",
    "name": "Up-down arrow",
    "cat": "symbols"
  },
  {
    "code": "arrow_up_small",
    "char": "🔼",
    "name": "Upwards button",
    "cat": "symbols"
  },
  {
    "code": "arrow_upper_left",
    "char": "↖",
    "name": "Up-left arrow",
    "cat": "symbols"
  },
  {
    "code": "arrow_upper_right",
    "char": "↗",
    "name": "Up-right arrow",
    "cat": "symbols"
  },
  {
    "code": "arrows_clockwise",
    "char": "🔃",
    "name": "Clockwise vertical arrows",
    "cat": "symbols"
  },
  {
    "code": "arrows_counterclockwise",
    "char": "🔄",
    "name": "Counterclockwise arrows button",
    "cat": "symbols"
  },
  {
    "code": "art",
    "char": "🎨",
    "name": "Artist palette",
    "cat": "symbols"
  },
  {
    "code": "articulated_lorry",
    "char": "🚛",
    "name": "Articulated lorry",
    "cat": "symbols"
  },
  {
    "code": "artificial_satellite",
    "char": "🛰",
    "name": "Satellite",
    "cat": "symbols"
  },
  {
    "code": "artist",
    "char": "🧑🎨",
    "name": "Artist",
    "cat": "people"
  },
  {
    "code": "aruba",
    "char": "🇦🇼",
    "name": "Flag: Aruba",
    "cat": "symbols"
  },
  {
    "code": "ascension_island",
    "char": "🇦🇨",
    "name": "Flag: Ascension Island",
    "cat": "symbols"
  },
  {
    "code": "asterisk",
    "char": "*⃣",
    "name": "Keycap: *",
    "cat": "symbols"
  },
  {
    "code": "astonished",
    "char": "😲",
    "name": "Astonished face",
    "cat": "people"
  },
  {
    "code": "astronaut",
    "char": "🧑🚀",
    "name": "Astronaut",
    "cat": "people"
  },
  {
    "code": "athletic_shoe",
    "char": "👟",
    "name": "Running shoe",
    "cat": "tech"
  },
  {
    "code": "atm",
    "char": "🏧",
    "name": "ATM sign",
    "cat": "symbols"
  },
  {
    "code": "atom_symbol",
    "char": "⚛",
    "name": "Atom symbol",
    "cat": "symbols"
  },
  {
    "code": "australia",
    "char": "🇦🇺",
    "name": "Flag: Australia",
    "cat": "symbols"
  },
  {
    "code": "austria",
    "char": "🇦🇹",
    "name": "Flag: Austria",
    "cat": "symbols"
  },
  {
    "code": "auto_rickshaw",
    "char": "🛺",
    "name": "Auto rickshaw",
    "cat": "symbols"
  },
  {
    "code": "avocado",
    "char": "🥑",
    "name": "Avocado",
    "cat": "symbols"
  },
  {
    "code": "axe",
    "char": "🪓",
    "name": "Axe",
    "cat": "tech"
  },
  {
    "code": "azerbaijan",
    "char": "🇦🇿",
    "name": "Flag: Azerbaijan",
    "cat": "symbols"
  },
  {
    "code": "b",
    "char": "🅱",
    "name": "B button (blood type)",
    "cat": "symbols"
  },
  {
    "code": "baby",
    "char": "👶",
    "name": "Baby",
    "cat": "people"
  },
  {
    "code": "baby_bottle",
    "char": "🍼",
    "name": "Baby bottle",
    "cat": "symbols"
  },
  {
    "code": "baby_chick",
    "char": "🐤",
    "name": "Baby chick",
    "cat": "symbols"
  },
  {
    "code": "baby_symbol",
    "char": "🚼",
    "name": "Baby symbol",
    "cat": "symbols"
  },
  {
    "code": "back",
    "char": "🔙",
    "name": "BACK arrow",
    "cat": "symbols"
  },
  {
    "code": "bacon",
    "char": "🥓",
    "name": "Bacon",
    "cat": "symbols"
  },
  {
    "code": "badger",
    "char": "🦡",
    "name": "Badger",
    "cat": "symbols"
  },
  {
    "code": "badminton",
    "char": "🏸",
    "name": "Badminton",
    "cat": "symbols"
  },
  {
    "code": "bagel",
    "char": "🥯",
    "name": "Bagel",
    "cat": "symbols"
  },
  {
    "code": "baggage_claim",
    "char": "🛄",
    "name": "Baggage claim",
    "cat": "symbols"
  },
  {
    "code": "baguette_bread",
    "char": "🥖",
    "name": "Baguette bread",
    "cat": "symbols"
  },
  {
    "code": "bahamas",
    "char": "🇧🇸",
    "name": "Flag: Bahamas",
    "cat": "symbols"
  },
  {
    "code": "bahrain",
    "char": "🇧🇭",
    "name": "Flag: Bahrain",
    "cat": "symbols"
  },
  {
    "code": "balance_scale",
    "char": "⚖",
    "name": "Balance scale",
    "cat": "tech"
  },
  {
    "code": "bald_man",
    "char": "👨🦲",
    "name": "Man: bald",
    "cat": "people"
  },
  {
    "code": "bald_woman",
    "char": "👩🦲",
    "name": "Woman: bald",
    "cat": "people"
  },
  {
    "code": "ballet_shoes",
    "char": "🩰",
    "name": "Ballet shoes",
    "cat": "tech"
  },
  {
    "code": "balloon",
    "char": "🎈",
    "name": "Balloon",
    "cat": "symbols"
  },
  {
    "code": "ballot_box",
    "char": "🗳",
    "name": "Ballot box with ballot",
    "cat": "tech"
  },
  {
    "code": "ballot_box_with_check",
    "char": "☑",
    "name": "Check box with check",
    "cat": "symbols"
  },
  {
    "code": "bamboo",
    "char": "🎍",
    "name": "Pine decoration",
    "cat": "symbols"
  },
  {
    "code": "banana",
    "char": "🍌",
    "name": "Banana",
    "cat": "symbols"
  },
  {
    "code": "bangbang",
    "char": "‼",
    "name": "Double exclamation mark",
    "cat": "symbols"
  },
  {
    "code": "bangladesh",
    "char": "🇧🇩",
    "name": "Flag: Bangladesh",
    "cat": "symbols"
  },
  {
    "code": "banjo",
    "char": "🪕",
    "name": "Banjo",
    "cat": "tech"
  },
  {
    "code": "bank",
    "char": "🏦",
    "name": "Bank",
    "cat": "symbols"
  },
  {
    "code": "bar_chart",
    "char": "📊",
    "name": "Bar chart",
    "cat": "tech"
  },
  {
    "code": "barbados",
    "char": "🇧🇧",
    "name": "Flag: Barbados",
    "cat": "symbols"
  },
  {
    "code": "barber",
    "char": "💈",
    "name": "Barber pole",
    "cat": "symbols"
  },
  {
    "code": "baseball",
    "char": "⚾",
    "name": "Baseball",
    "cat": "symbols"
  },
  {
    "code": "basket",
    "char": "🧺",
    "name": "Basket",
    "cat": "tech"
  },
  {
    "code": "basketball",
    "char": "🏀",
    "name": "Basketball",
    "cat": "symbols"
  },
  {
    "code": "basketball_man",
    "char": "⛹♂",
    "name": "Man bouncing ball",
    "cat": "people"
  },
  {
    "code": "basketball_woman",
    "char": "⛹♀",
    "name": "Woman bouncing ball",
    "cat": "people"
  },
  {
    "code": "bat",
    "char": "🦇",
    "name": "Bat",
    "cat": "symbols"
  },
  {
    "code": "bath",
    "char": "🛀",
    "name": "Person taking bath",
    "cat": "people"
  },
  {
    "code": "bathtub",
    "char": "🛁",
    "name": "Bathtub",
    "cat": "tech"
  },
  {
    "code": "battery",
    "char": "🔋",
    "name": "Battery",
    "cat": "tech"
  },
  {
    "code": "beach_umbrella",
    "char": "🏖",
    "name": "Beach with umbrella",
    "cat": "symbols"
  },
  {
    "code": "beans",
    "char": "🫘",
    "name": "Beans",
    "cat": "symbols"
  },
  {
    "code": "bear",
    "char": "🐻",
    "name": "Bear",
    "cat": "symbols"
  },
  {
    "code": "bearded_person",
    "char": "🧔",
    "name": "Person: beard",
    "cat": "people"
  },
  {
    "code": "beaver",
    "char": "🦫",
    "name": "Beaver",
    "cat": "symbols"
  },
  {
    "code": "bed",
    "char": "🛏",
    "name": "Bed",
    "cat": "tech"
  },
  {
    "code": "bee",
    "char": "🐝",
    "name": "Honeybee",
    "cat": "symbols"
  },
  {
    "code": "beer",
    "char": "🍺",
    "name": "Beer mug",
    "cat": "symbols"
  },
  {
    "code": "beers",
    "char": "🍻",
    "name": "Clinking beer mugs",
    "cat": "symbols"
  },
  {
    "code": "beetle",
    "char": "🪲",
    "name": "Beetle",
    "cat": "symbols"
  },
  {
    "code": "beginner",
    "char": "🔰",
    "name": "Japanese symbol for beginner",
    "cat": "symbols"
  },
  {
    "code": "belarus",
    "char": "🇧🇾",
    "name": "Flag: Belarus",
    "cat": "symbols"
  },
  {
    "code": "belgium",
    "char": "🇧🇪",
    "name": "Flag: Belgium",
    "cat": "symbols"
  },
  {
    "code": "belize",
    "char": "🇧🇿",
    "name": "Flag: Belize",
    "cat": "symbols"
  },
  {
    "code": "bell",
    "char": "🔔",
    "name": "Bell",
    "cat": "status"
  },
  {
    "code": "bell_pepper",
    "char": "🫑",
    "name": "Bell pepper",
    "cat": "symbols"
  },
  {
    "code": "bellhop_bell",
    "char": "🛎",
    "name": "Bellhop bell",
    "cat": "symbols"
  },
  {
    "code": "benin",
    "char": "🇧🇯",
    "name": "Flag: Benin",
    "cat": "symbols"
  },
  {
    "code": "bento",
    "char": "🍱",
    "name": "Bento box",
    "cat": "symbols"
  },
  {
    "code": "bermuda",
    "char": "🇧🇲",
    "name": "Flag: Bermuda",
    "cat": "symbols"
  },
  {
    "code": "beverage_box",
    "char": "🧃",
    "name": "Beverage box",
    "cat": "symbols"
  },
  {
    "code": "bhutan",
    "char": "🇧🇹",
    "name": "Flag: Bhutan",
    "cat": "symbols"
  },
  {
    "code": "bicyclist",
    "char": "🚴",
    "name": "Person biking",
    "cat": "people"
  },
  {
    "code": "bike",
    "char": "🚲",
    "name": "Bicycle",
    "cat": "symbols"
  },
  {
    "code": "biking_man",
    "char": "🚴♂",
    "name": "Man biking",
    "cat": "people"
  },
  {
    "code": "biking_woman",
    "char": "🚴♀",
    "name": "Woman biking",
    "cat": "people"
  },
  {
    "code": "bikini",
    "char": "👙",
    "name": "Bikini",
    "cat": "tech"
  },
  {
    "code": "billed_cap",
    "char": "🧢",
    "name": "Billed cap",
    "cat": "tech"
  },
  {
    "code": "biohazard",
    "char": "☣",
    "name": "Biohazard",
    "cat": "status"
  },
  {
    "code": "bird",
    "char": "🐦",
    "name": "Bird",
    "cat": "symbols"
  },
  {
    "code": "birthday",
    "char": "🎂",
    "name": "Birthday cake",
    "cat": "symbols"
  },
  {
    "code": "bison",
    "char": "🦬",
    "name": "Bison",
    "cat": "symbols"
  },
  {
    "code": "biting_lip",
    "char": "🫦",
    "name": "Biting lip",
    "cat": "people"
  },
  {
    "code": "black_bird",
    "char": "🐦⬛",
    "name": "Black bird",
    "cat": "symbols"
  },
  {
    "code": "black_cat",
    "char": "🐈⬛",
    "name": "Black cat",
    "cat": "symbols"
  },
  {
    "code": "black_circle",
    "char": "⚫",
    "name": "Black circle",
    "cat": "status"
  },
  {
    "code": "black_flag",
    "char": "🏴",
    "name": "Black flag",
    "cat": "symbols"
  },
  {
    "code": "black_heart",
    "char": "🖤",
    "name": "Black heart",
    "cat": "people"
  },
  {
    "code": "black_joker",
    "char": "🃏",
    "name": "Joker",
    "cat": "symbols"
  },
  {
    "code": "black_large_square",
    "char": "⬛",
    "name": "Black large square",
    "cat": "symbols"
  },
  {
    "code": "black_medium_small_square",
    "char": "◾",
    "name": "Black medium-small square",
    "cat": "symbols"
  },
  {
    "code": "black_medium_square",
    "char": "◼",
    "name": "Black medium square",
    "cat": "symbols"
  },
  {
    "code": "black_nib",
    "char": "✒",
    "name": "Black nib",
    "cat": "tech"
  },
  {
    "code": "black_small_square",
    "char": "▪",
    "name": "Black small square",
    "cat": "symbols"
  },
  {
    "code": "black_square_button",
    "char": "🔲",
    "name": "Black square button",
    "cat": "symbols"
  },
  {
    "code": "blond_haired_man",
    "char": "👱♂",
    "name": "Man: blond hair",
    "cat": "people"
  },
  {
    "code": "blond_haired_person",
    "char": "👱",
    "name": "Person: blond hair",
    "cat": "people"
  },
  {
    "code": "blond_haired_woman",
    "char": "👱♀",
    "name": "Woman: blond hair",
    "cat": "people"
  },
  {
    "code": "blonde_woman",
    "char": "👱♀",
    "name": "Woman: blond hair",
    "cat": "people"
  },
  {
    "code": "blossom",
    "char": "🌼",
    "name": "Blossom",
    "cat": "symbols"
  },
  {
    "code": "blowfish",
    "char": "🐡",
    "name": "Blowfish",
    "cat": "symbols"
  },
  {
    "code": "blue_book",
    "char": "📘",
    "name": "Blue book",
    "cat": "tech"
  },
  {
    "code": "blue_car",
    "char": "🚙",
    "name": "Sport utility vehicle",
    "cat": "symbols"
  },
  {
    "code": "blue_heart",
    "char": "💙",
    "name": "Blue heart",
    "cat": "people"
  },
  {
    "code": "blue_square",
    "char": "🟦",
    "name": "Blue square",
    "cat": "symbols"
  },
  {
    "code": "blueberries",
    "char": "🫐",
    "name": "Blueberries",
    "cat": "symbols"
  },
  {
    "code": "blush",
    "char": "😊",
    "name": "Smiling face with smiling eyes",
    "cat": "people"
  },
  {
    "code": "boar",
    "char": "🐗",
    "name": "Boar",
    "cat": "symbols"
  },
  {
    "code": "boat",
    "char": "⛵",
    "name": "Sailboat",
    "cat": "symbols"
  },
  {
    "code": "bolivia",
    "char": "🇧🇴",
    "name": "Flag: Bolivia",
    "cat": "symbols"
  },
  {
    "code": "bomb",
    "char": "💣",
    "name": "Bomb",
    "cat": "tech"
  },
  {
    "code": "bone",
    "char": "🦴",
    "name": "Bone",
    "cat": "people"
  },
  {
    "code": "book",
    "char": "📖",
    "name": "Open book",
    "cat": "tech"
  },
  {
    "code": "bookmark",
    "char": "🔖",
    "name": "Bookmark",
    "cat": "tech"
  },
  {
    "code": "bookmark_tabs",
    "char": "📑",
    "name": "Bookmark tabs",
    "cat": "tech"
  },
  {
    "code": "books",
    "char": "📚",
    "name": "Books",
    "cat": "tech"
  },
  {
    "code": "boom",
    "char": "💥",
    "name": "Collision",
    "cat": "people"
  },
  {
    "code": "boomerang",
    "char": "🪃",
    "name": "Boomerang",
    "cat": "tech"
  },
  {
    "code": "boot",
    "char": "👢",
    "name": "Woman’s boot",
    "cat": "tech"
  },
  {
    "code": "bosnia_herzegovina",
    "char": "🇧🇦",
    "name": "Flag: Bosnia & Herzegovina",
    "cat": "symbols"
  },
  {
    "code": "botswana",
    "char": "🇧🇼",
    "name": "Flag: Botswana",
    "cat": "symbols"
  },
  {
    "code": "bouncing_ball_man",
    "char": "⛹♂",
    "name": "Man bouncing ball",
    "cat": "people"
  },
  {
    "code": "bouncing_ball_person",
    "char": "⛹",
    "name": "Person bouncing ball",
    "cat": "people"
  },
  {
    "code": "bouncing_ball_woman",
    "char": "⛹♀",
    "name": "Woman bouncing ball",
    "cat": "people"
  },
  {
    "code": "bouquet",
    "char": "💐",
    "name": "Bouquet",
    "cat": "symbols"
  },
  {
    "code": "bouvet_island",
    "char": "🇧🇻",
    "name": "Flag: Bouvet Island",
    "cat": "symbols"
  },
  {
    "code": "bow",
    "char": "🙇",
    "name": "Person bowing",
    "cat": "people"
  },
  {
    "code": "bow_and_arrow",
    "char": "🏹",
    "name": "Bow and arrow",
    "cat": "tech"
  },
  {
    "code": "bowing_man",
    "char": "🙇♂",
    "name": "Man bowing",
    "cat": "people"
  },
  {
    "code": "bowing_woman",
    "char": "🙇♀",
    "name": "Woman bowing",
    "cat": "people"
  },
  {
    "code": "bowl_with_spoon",
    "char": "🥣",
    "name": "Bowl with spoon",
    "cat": "symbols"
  },
  {
    "code": "bowling",
    "char": "🎳",
    "name": "Bowling",
    "cat": "symbols"
  },
  {
    "code": "boxing_glove",
    "char": "🥊",
    "name": "Boxing glove",
    "cat": "symbols"
  },
  {
    "code": "boy",
    "char": "👦",
    "name": "Boy",
    "cat": "people"
  },
  {
    "code": "brain",
    "char": "🧠",
    "name": "Brain",
    "cat": "people"
  },
  {
    "code": "brazil",
    "char": "🇧🇷",
    "name": "Flag: Brazil",
    "cat": "symbols"
  },
  {
    "code": "bread",
    "char": "🍞",
    "name": "Bread",
    "cat": "symbols"
  },
  {
    "code": "breast_feeding",
    "char": "🤱",
    "name": "Breast-feeding",
    "cat": "people"
  },
  {
    "code": "bricks",
    "char": "🧱",
    "name": "Brick",
    "cat": "symbols"
  },
  {
    "code": "bride_with_veil",
    "char": "👰♀",
    "name": "Woman with veil",
    "cat": "people"
  },
  {
    "code": "bridge_at_night",
    "char": "🌉",
    "name": "Bridge at night",
    "cat": "symbols"
  },
  {
    "code": "briefcase",
    "char": "💼",
    "name": "Briefcase",
    "cat": "tech"
  },
  {
    "code": "british_indian_ocean_territory",
    "char": "🇮🇴",
    "name": "Flag: British Indian Ocean Territory",
    "cat": "symbols"
  },
  {
    "code": "british_virgin_islands",
    "char": "🇻🇬",
    "name": "Flag: British Virgin Islands",
    "cat": "symbols"
  },
  {
    "code": "broccoli",
    "char": "🥦",
    "name": "Broccoli",
    "cat": "symbols"
  },
  {
    "code": "broken_heart",
    "char": "💔",
    "name": "Broken heart",
    "cat": "people"
  },
  {
    "code": "broom",
    "char": "🧹",
    "name": "Broom",
    "cat": "tech"
  },
  {
    "code": "brown_circle",
    "char": "🟤",
    "name": "Brown circle",
    "cat": "symbols"
  },
  {
    "code": "brown_heart",
    "char": "🤎",
    "name": "Brown heart",
    "cat": "people"
  },
  {
    "code": "brown_square",
    "char": "🟫",
    "name": "Brown square",
    "cat": "symbols"
  },
  {
    "code": "brunei",
    "char": "🇧🇳",
    "name": "Flag: Brunei",
    "cat": "symbols"
  },
  {
    "code": "bubble_tea",
    "char": "🧋",
    "name": "Bubble tea",
    "cat": "symbols"
  },
  {
    "code": "bubbles",
    "char": "🫧",
    "name": "Bubbles",
    "cat": "tech"
  },
  {
    "code": "bucket",
    "char": "🪣",
    "name": "Bucket",
    "cat": "tech"
  },
  {
    "code": "building_construction",
    "char": "🏗",
    "name": "Building construction",
    "cat": "symbols"
  },
  {
    "code": "bulb",
    "char": "💡",
    "name": "Light bulb",
    "cat": "status"
  },
  {
    "code": "bulgaria",
    "char": "🇧🇬",
    "name": "Flag: Bulgaria",
    "cat": "symbols"
  },
  {
    "code": "bullettrain_front",
    "char": "🚅",
    "name": "Bullet train",
    "cat": "symbols"
  },
  {
    "code": "bullettrain_side",
    "char": "🚄",
    "name": "High-speed train",
    "cat": "symbols"
  },
  {
    "code": "burkina_faso",
    "char": "🇧🇫",
    "name": "Flag: Burkina Faso",
    "cat": "symbols"
  },
  {
    "code": "burrito",
    "char": "🌯",
    "name": "Burrito",
    "cat": "symbols"
  },
  {
    "code": "burundi",
    "char": "🇧🇮",
    "name": "Flag: Burundi",
    "cat": "symbols"
  },
  {
    "code": "bus",
    "char": "🚌",
    "name": "Bus",
    "cat": "symbols"
  },
  {
    "code": "business_suit_levitating",
    "char": "🕴",
    "name": "Person in suit levitating",
    "cat": "people"
  },
  {
    "code": "busstop",
    "char": "🚏",
    "name": "Bus stop",
    "cat": "symbols"
  },
  {
    "code": "bust_in_silhouette",
    "char": "👤",
    "name": "Bust in silhouette",
    "cat": "people"
  },
  {
    "code": "busts_in_silhouette",
    "char": "👥",
    "name": "Busts in silhouette",
    "cat": "people"
  },
  {
    "code": "butter",
    "char": "🧈",
    "name": "Butter",
    "cat": "symbols"
  },
  {
    "code": "butterfly",
    "char": "🦋",
    "name": "Butterfly",
    "cat": "symbols"
  },
  {
    "code": "cactus",
    "char": "🌵",
    "name": "Cactus",
    "cat": "symbols"
  },
  {
    "code": "cake",
    "char": "🍰",
    "name": "Shortcake",
    "cat": "symbols"
  },
  {
    "code": "calendar",
    "char": "📆",
    "name": "Tear-off calendar",
    "cat": "tech"
  },
  {
    "code": "call_me_hand",
    "char": "🤙",
    "name": "Call me hand",
    "cat": "people"
  },
  {
    "code": "calling",
    "char": "📲",
    "name": "Mobile phone with arrow",
    "cat": "tech"
  },
  {
    "code": "cambodia",
    "char": "🇰🇭",
    "name": "Flag: Cambodia",
    "cat": "symbols"
  },
  {
    "code": "camel",
    "char": "🐫",
    "name": "Two-hump camel",
    "cat": "symbols"
  },
  {
    "code": "camera",
    "char": "📷",
    "name": "Camera",
    "cat": "tech"
  },
  {
    "code": "camera_flash",
    "char": "📸",
    "name": "Camera with flash",
    "cat": "tech"
  },
  {
    "code": "cameroon",
    "char": "🇨🇲",
    "name": "Flag: Cameroon",
    "cat": "symbols"
  },
  {
    "code": "camping",
    "char": "🏕",
    "name": "Camping",
    "cat": "symbols"
  },
  {
    "code": "canada",
    "char": "🇨🇦",
    "name": "Flag: Canada",
    "cat": "symbols"
  },
  {
    "code": "canary_islands",
    "char": "🇮🇨",
    "name": "Flag: Canary Islands",
    "cat": "symbols"
  },
  {
    "code": "cancer",
    "char": "♋",
    "name": "Cancer",
    "cat": "symbols"
  },
  {
    "code": "candle",
    "char": "🕯",
    "name": "Candle",
    "cat": "tech"
  },
  {
    "code": "candy",
    "char": "🍬",
    "name": "Candy",
    "cat": "symbols"
  },
  {
    "code": "canned_food",
    "char": "🥫",
    "name": "Canned food",
    "cat": "symbols"
  },
  {
    "code": "canoe",
    "char": "🛶",
    "name": "Canoe",
    "cat": "symbols"
  },
  {
    "code": "cape_verde",
    "char": "🇨🇻",
    "name": "Flag: Cape Verde",
    "cat": "symbols"
  },
  {
    "code": "capital_abcd",
    "char": "🔠",
    "name": "Input latin uppercase",
    "cat": "symbols"
  },
  {
    "code": "capricorn",
    "char": "♑",
    "name": "Capricorn",
    "cat": "symbols"
  },
  {
    "code": "car",
    "char": "🚗",
    "name": "Automobile",
    "cat": "symbols"
  },
  {
    "code": "card_file_box",
    "char": "🗃",
    "name": "Card file box",
    "cat": "tech"
  },
  {
    "code": "card_index",
    "char": "📇",
    "name": "Card index",
    "cat": "tech"
  },
  {
    "code": "card_index_dividers",
    "char": "🗂",
    "name": "Card index dividers",
    "cat": "tech"
  },
  {
    "code": "caribbean_netherlands",
    "char": "🇧🇶",
    "name": "Flag: Caribbean Netherlands",
    "cat": "symbols"
  },
  {
    "code": "carousel_horse",
    "char": "🎠",
    "name": "Carousel horse",
    "cat": "symbols"
  },
  {
    "code": "carpentry_saw",
    "char": "🪚",
    "name": "Carpentry saw",
    "cat": "tech"
  },
  {
    "code": "carrot",
    "char": "🥕",
    "name": "Carrot",
    "cat": "symbols"
  },
  {
    "code": "cartwheeling",
    "char": "🤸",
    "name": "Person cartwheeling",
    "cat": "people"
  },
  {
    "code": "cat",
    "char": "🐱",
    "name": "Cat face",
    "cat": "symbols"
  },
  {
    "code": "cat2",
    "char": "🐈",
    "name": "Cat",
    "cat": "symbols"
  },
  {
    "code": "cayman_islands",
    "char": "🇰🇾",
    "name": "Flag: Cayman Islands",
    "cat": "symbols"
  },
  {
    "code": "cd",
    "char": "💿",
    "name": "Optical disk",
    "cat": "tech"
  },
  {
    "code": "central_african_republic",
    "char": "🇨🇫",
    "name": "Flag: Central African Republic",
    "cat": "symbols"
  },
  {
    "code": "ceuta_melilla",
    "char": "🇪🇦",
    "name": "Flag: Ceuta & Melilla",
    "cat": "symbols"
  },
  {
    "code": "chad",
    "char": "🇹🇩",
    "name": "Flag: Chad",
    "cat": "symbols"
  },
  {
    "code": "chains",
    "char": "⛓",
    "name": "Chains",
    "cat": "tech"
  },
  {
    "code": "chair",
    "char": "🪑",
    "name": "Chair",
    "cat": "tech"
  },
  {
    "code": "champagne",
    "char": "🍾",
    "name": "Bottle with popping cork",
    "cat": "symbols"
  },
  {
    "code": "chart",
    "char": "💹",
    "name": "Chart increasing with yen",
    "cat": "tech"
  },
  {
    "code": "chart_with_downwards_trend",
    "char": "📉",
    "name": "Chart decreasing",
    "cat": "tech"
  },
  {
    "code": "chart_with_upwards_trend",
    "char": "📈",
    "name": "Chart increasing",
    "cat": "tech"
  },
  {
    "code": "cheese",
    "char": "🧀",
    "name": "Cheese wedge",
    "cat": "symbols"
  },
  {
    "code": "cherries",
    "char": "🍒",
    "name": "Cherries",
    "cat": "symbols"
  },
  {
    "code": "cherry_blossom",
    "char": "🌸",
    "name": "Cherry blossom",
    "cat": "symbols"
  },
  {
    "code": "chess_pawn",
    "char": "♟",
    "name": "Chess pawn",
    "cat": "symbols"
  },
  {
    "code": "chestnut",
    "char": "🌰",
    "name": "Chestnut",
    "cat": "symbols"
  },
  {
    "code": "chicken",
    "char": "🐔",
    "name": "Chicken",
    "cat": "symbols"
  },
  {
    "code": "child",
    "char": "🧒",
    "name": "Child",
    "cat": "people"
  },
  {
    "code": "children_crossing",
    "char": "🚸",
    "name": "Children crossing",
    "cat": "symbols"
  },
  {
    "code": "chile",
    "char": "🇨🇱",
    "name": "Flag: Chile",
    "cat": "symbols"
  },
  {
    "code": "chipmunk",
    "char": "🐿",
    "name": "Chipmunk",
    "cat": "symbols"
  },
  {
    "code": "chocolate_bar",
    "char": "🍫",
    "name": "Chocolate bar",
    "cat": "symbols"
  },
  {
    "code": "chopsticks",
    "char": "🥢",
    "name": "Chopsticks",
    "cat": "symbols"
  },
  {
    "code": "christmas_island",
    "char": "🇨🇽",
    "name": "Flag: Christmas Island",
    "cat": "symbols"
  },
  {
    "code": "christmas_tree",
    "char": "🎄",
    "name": "Christmas tree",
    "cat": "symbols"
  },
  {
    "code": "church",
    "char": "⛪",
    "name": "Church",
    "cat": "symbols"
  },
  {
    "code": "cinema",
    "char": "🎦",
    "name": "Cinema",
    "cat": "symbols"
  },
  {
    "code": "circus_tent",
    "char": "🎪",
    "name": "Circus tent",
    "cat": "symbols"
  },
  {
    "code": "city_sunrise",
    "char": "🌇",
    "name": "Sunset",
    "cat": "symbols"
  },
  {
    "code": "city_sunset",
    "char": "🌆",
    "name": "Cityscape at dusk",
    "cat": "symbols"
  },
  {
    "code": "cityscape",
    "char": "🏙",
    "name": "Cityscape",
    "cat": "symbols"
  },
  {
    "code": "cl",
    "char": "🆑",
    "name": "CL button",
    "cat": "symbols"
  },
  {
    "code": "clamp",
    "char": "🗜",
    "name": "Clamp",
    "cat": "tech"
  },
  {
    "code": "clapper",
    "char": "🎬",
    "name": "Clapper board",
    "cat": "tech"
  },
  {
    "code": "classical_building",
    "char": "🏛",
    "name": "Classical building",
    "cat": "symbols"
  },
  {
    "code": "climbing",
    "char": "🧗",
    "name": "Person climbing",
    "cat": "people"
  },
  {
    "code": "climbing_man",
    "char": "🧗♂",
    "name": "Man climbing",
    "cat": "people"
  },
  {
    "code": "climbing_woman",
    "char": "🧗♀",
    "name": "Woman climbing",
    "cat": "people"
  },
  {
    "code": "clinking_glasses",
    "char": "🥂",
    "name": "Clinking glasses",
    "cat": "symbols"
  },
  {
    "code": "clipboard",
    "char": "📋",
    "name": "Clipboard",
    "cat": "tech"
  },
  {
    "code": "clipperton_island",
    "char": "🇨🇵",
    "name": "Flag: Clipperton Island",
    "cat": "symbols"
  },
  {
    "code": "clock1",
    "char": "🕐",
    "name": "One o’clock",
    "cat": "symbols"
  },
  {
    "code": "clock10",
    "char": "🕙",
    "name": "Ten o’clock",
    "cat": "symbols"
  },
  {
    "code": "clock1030",
    "char": "🕥",
    "name": "Ten-thirty",
    "cat": "symbols"
  },
  {
    "code": "clock11",
    "char": "🕚",
    "name": "Eleven o’clock",
    "cat": "symbols"
  },
  {
    "code": "clock1130",
    "char": "🕦",
    "name": "Eleven-thirty",
    "cat": "symbols"
  },
  {
    "code": "clock12",
    "char": "🕛",
    "name": "Twelve o’clock",
    "cat": "symbols"
  },
  {
    "code": "clock1230",
    "char": "🕧",
    "name": "Twelve-thirty",
    "cat": "symbols"
  },
  {
    "code": "clock130",
    "char": "🕜",
    "name": "One-thirty",
    "cat": "symbols"
  },
  {
    "code": "clock2",
    "char": "🕑",
    "name": "Two o’clock",
    "cat": "symbols"
  },
  {
    "code": "clock230",
    "char": "🕝",
    "name": "Two-thirty",
    "cat": "symbols"
  },
  {
    "code": "clock3",
    "char": "🕒",
    "name": "Three o’clock",
    "cat": "symbols"
  },
  {
    "code": "clock330",
    "char": "🕞",
    "name": "Three-thirty",
    "cat": "symbols"
  },
  {
    "code": "clock4",
    "char": "🕓",
    "name": "Four o’clock",
    "cat": "symbols"
  },
  {
    "code": "clock430",
    "char": "🕟",
    "name": "Four-thirty",
    "cat": "symbols"
  },
  {
    "code": "clock5",
    "char": "🕔",
    "name": "Five o’clock",
    "cat": "symbols"
  },
  {
    "code": "clock530",
    "char": "🕠",
    "name": "Five-thirty",
    "cat": "symbols"
  },
  {
    "code": "clock6",
    "char": "🕕",
    "name": "Six o’clock",
    "cat": "symbols"
  },
  {
    "code": "clock630",
    "char": "🕡",
    "name": "Six-thirty",
    "cat": "symbols"
  },
  {
    "code": "clock7",
    "char": "🕖",
    "name": "Seven o’clock",
    "cat": "symbols"
  },
  {
    "code": "clock730",
    "char": "🕢",
    "name": "Seven-thirty",
    "cat": "symbols"
  },
  {
    "code": "clock8",
    "char": "🕗",
    "name": "Eight o’clock",
    "cat": "symbols"
  },
  {
    "code": "clock830",
    "char": "🕣",
    "name": "Eight-thirty",
    "cat": "symbols"
  },
  {
    "code": "clock9",
    "char": "🕘",
    "name": "Nine o’clock",
    "cat": "symbols"
  },
  {
    "code": "clock930",
    "char": "🕤",
    "name": "Nine-thirty",
    "cat": "symbols"
  },
  {
    "code": "closed_book",
    "char": "📕",
    "name": "Closed book",
    "cat": "tech"
  },
  {
    "code": "closed_lock_with_key",
    "char": "🔐",
    "name": "Locked with key",
    "cat": "tech"
  },
  {
    "code": "closed_umbrella",
    "char": "🌂",
    "name": "Closed umbrella",
    "cat": "symbols"
  },
  {
    "code": "cloud",
    "char": "☁",
    "name": "Cloud",
    "cat": "tech"
  },
  {
    "code": "cloud_with_lightning",
    "char": "🌩",
    "name": "Cloud with lightning",
    "cat": "symbols"
  },
  {
    "code": "cloud_with_lightning_and_rain",
    "char": "⛈",
    "name": "Cloud with lightning and rain",
    "cat": "symbols"
  },
  {
    "code": "cloud_with_rain",
    "char": "🌧",
    "name": "Cloud with rain",
    "cat": "symbols"
  },
  {
    "code": "cloud_with_snow",
    "char": "🌨",
    "name": "Cloud with snow",
    "cat": "symbols"
  },
  {
    "code": "clown_face",
    "char": "🤡",
    "name": "Clown face",
    "cat": "people"
  },
  {
    "code": "clubs",
    "char": "♣",
    "name": "Club suit",
    "cat": "symbols"
  },
  {
    "code": "cn",
    "char": "🇨🇳",
    "name": "Flag: China",
    "cat": "symbols"
  },
  {
    "code": "coat",
    "char": "🧥",
    "name": "Coat",
    "cat": "tech"
  },
  {
    "code": "cockroach",
    "char": "🪳",
    "name": "Cockroach",
    "cat": "symbols"
  },
  {
    "code": "cocktail",
    "char": "🍸",
    "name": "Cocktail glass",
    "cat": "symbols"
  },
  {
    "code": "coconut",
    "char": "🥥",
    "name": "Coconut",
    "cat": "symbols"
  },
  {
    "code": "cocos_islands",
    "char": "🇨🇨",
    "name": "Flag: Cocos (Keeling) Islands",
    "cat": "symbols"
  },
  {
    "code": "coffee",
    "char": "☕",
    "name": "Hot beverage",
    "cat": "symbols"
  },
  {
    "code": "coffin",
    "char": "⚰",
    "name": "Coffin",
    "cat": "tech"
  },
  {
    "code": "coin",
    "char": "🪙",
    "name": "Coin",
    "cat": "tech"
  },
  {
    "code": "cold_face",
    "char": "🥶",
    "name": "Cold face",
    "cat": "people"
  },
  {
    "code": "cold_sweat",
    "char": "😰",
    "name": "Anxious face with sweat",
    "cat": "people"
  },
  {
    "code": "collision",
    "char": "💥",
    "name": "Collision",
    "cat": "people"
  },
  {
    "code": "colombia",
    "char": "🇨🇴",
    "name": "Flag: Colombia",
    "cat": "symbols"
  },
  {
    "code": "comet",
    "char": "☄",
    "name": "Comet",
    "cat": "symbols"
  },
  {
    "code": "comoros",
    "char": "🇰🇲",
    "name": "Flag: Comoros",
    "cat": "symbols"
  },
  {
    "code": "compass",
    "char": "🧭",
    "name": "Compass",
    "cat": "symbols"
  },
  {
    "code": "computer_mouse",
    "char": "🖱",
    "name": "Computer mouse",
    "cat": "tech"
  },
  {
    "code": "confetti_ball",
    "char": "🎊",
    "name": "Confetti ball",
    "cat": "symbols"
  },
  {
    "code": "confounded",
    "char": "😖",
    "name": "Confounded face",
    "cat": "people"
  },
  {
    "code": "confused",
    "char": "😕",
    "name": "Confused face",
    "cat": "people"
  },
  {
    "code": "congo_brazzaville",
    "char": "🇨🇬",
    "name": "Flag: Congo - Brazzaville",
    "cat": "symbols"
  },
  {
    "code": "congo_kinshasa",
    "char": "🇨🇩",
    "name": "Flag: Congo - Kinshasa",
    "cat": "symbols"
  },
  {
    "code": "congratulations",
    "char": "㊗",
    "name": "Japanese “congratulations” button",
    "cat": "symbols"
  },
  {
    "code": "construction",
    "char": "🚧",
    "name": "Construction",
    "cat": "status"
  },
  {
    "code": "construction_worker",
    "char": "👷",
    "name": "Construction worker",
    "cat": "people"
  },
  {
    "code": "construction_worker_man",
    "char": "👷♂",
    "name": "Man construction worker",
    "cat": "people"
  },
  {
    "code": "construction_worker_woman",
    "char": "👷♀",
    "name": "Woman construction worker",
    "cat": "people"
  },
  {
    "code": "control_knobs",
    "char": "🎛",
    "name": "Control knobs",
    "cat": "tech"
  },
  {
    "code": "convenience_store",
    "char": "🏪",
    "name": "Convenience store",
    "cat": "symbols"
  },
  {
    "code": "cook",
    "char": "🧑🍳",
    "name": "Cook",
    "cat": "people"
  },
  {
    "code": "cook_islands",
    "char": "🇨🇰",
    "name": "Flag: Cook Islands",
    "cat": "symbols"
  },
  {
    "code": "cookie",
    "char": "🍪",
    "name": "Cookie",
    "cat": "symbols"
  },
  {
    "code": "cool",
    "char": "🆒",
    "name": "COOL button",
    "cat": "symbols"
  },
  {
    "code": "cop",
    "char": "👮",
    "name": "Police officer",
    "cat": "people"
  },
  {
    "code": "copyright",
    "char": "©",
    "name": "Copyright",
    "cat": "symbols"
  },
  {
    "code": "coral",
    "char": "🪸",
    "name": "Coral",
    "cat": "symbols"
  },
  {
    "code": "corn",
    "char": "🌽",
    "name": "Ear of corn",
    "cat": "symbols"
  },
  {
    "code": "costa_rica",
    "char": "🇨🇷",
    "name": "Flag: Costa Rica",
    "cat": "symbols"
  },
  {
    "code": "cote_divoire",
    "char": "🇨🇮",
    "name": "Flag: Côte d’Ivoire",
    "cat": "symbols"
  },
  {
    "code": "couch_and_lamp",
    "char": "🛋",
    "name": "Couch and lamp",
    "cat": "tech"
  },
  {
    "code": "couple",
    "char": "👫",
    "name": "Woman and man holding hands",
    "cat": "people"
  },
  {
    "code": "couple_with_heart",
    "char": "💑",
    "name": "Couple with heart",
    "cat": "people"
  },
  {
    "code": "couple_with_heart_man_man",
    "char": "👨❤👨",
    "name": "Couple with heart: man, man",
    "cat": "people"
  },
  {
    "code": "couple_with_heart_woman_man",
    "char": "👩❤👨",
    "name": "Couple with heart: woman, man",
    "cat": "people"
  },
  {
    "code": "couple_with_heart_woman_woman",
    "char": "👩❤👩",
    "name": "Couple with heart: woman, woman",
    "cat": "people"
  },
  {
    "code": "couplekiss",
    "char": "💏",
    "name": "Kiss",
    "cat": "people"
  },
  {
    "code": "couplekiss_man_man",
    "char": "👨❤💋👨",
    "name": "Kiss: man, man",
    "cat": "people"
  },
  {
    "code": "couplekiss_man_woman",
    "char": "👩❤💋👨",
    "name": "Kiss: woman, man",
    "cat": "people"
  },
  {
    "code": "couplekiss_woman_woman",
    "char": "👩❤💋👩",
    "name": "Kiss: woman, woman",
    "cat": "people"
  },
  {
    "code": "cow",
    "char": "🐮",
    "name": "Cow face",
    "cat": "symbols"
  },
  {
    "code": "cow2",
    "char": "🐄",
    "name": "Cow",
    "cat": "symbols"
  },
  {
    "code": "cowboy_hat_face",
    "char": "🤠",
    "name": "Cowboy hat face",
    "cat": "people"
  },
  {
    "code": "crab",
    "char": "🦀",
    "name": "Crab",
    "cat": "symbols"
  },
  {
    "code": "crayon",
    "char": "🖍",
    "name": "Crayon",
    "cat": "tech"
  },
  {
    "code": "credit_card",
    "char": "💳",
    "name": "Credit card",
    "cat": "tech"
  },
  {
    "code": "crescent_moon",
    "char": "🌙",
    "name": "Crescent moon",
    "cat": "symbols"
  },
  {
    "code": "cricket",
    "char": "🦗",
    "name": "Cricket",
    "cat": "symbols"
  },
  {
    "code": "cricket_game",
    "char": "🏏",
    "name": "Cricket game",
    "cat": "symbols"
  },
  {
    "code": "croatia",
    "char": "🇭🇷",
    "name": "Flag: Croatia",
    "cat": "symbols"
  },
  {
    "code": "crocodile",
    "char": "🐊",
    "name": "Crocodile",
    "cat": "symbols"
  },
  {
    "code": "croissant",
    "char": "🥐",
    "name": "Croissant",
    "cat": "symbols"
  },
  {
    "code": "crossed_fingers",
    "char": "🤞",
    "name": "Crossed fingers",
    "cat": "people"
  },
  {
    "code": "crossed_flags",
    "char": "🎌",
    "name": "Crossed flags",
    "cat": "symbols"
  },
  {
    "code": "crossed_swords",
    "char": "⚔",
    "name": "Crossed swords",
    "cat": "tech"
  },
  {
    "code": "crown",
    "char": "👑",
    "name": "Crown",
    "cat": "tech"
  },
  {
    "code": "crutch",
    "char": "🩼",
    "name": "Crutch",
    "cat": "tech"
  },
  {
    "code": "cry",
    "char": "😢",
    "name": "Crying face",
    "cat": "people"
  },
  {
    "code": "crying_cat_face",
    "char": "😿",
    "name": "Crying cat",
    "cat": "people"
  },
  {
    "code": "crystal_ball",
    "char": "🔮",
    "name": "Crystal ball",
    "cat": "symbols"
  },
  {
    "code": "cuba",
    "char": "🇨🇺",
    "name": "Flag: Cuba",
    "cat": "symbols"
  },
  {
    "code": "cucumber",
    "char": "🥒",
    "name": "Cucumber",
    "cat": "symbols"
  },
  {
    "code": "cup_with_straw",
    "char": "🥤",
    "name": "Cup with straw",
    "cat": "symbols"
  },
  {
    "code": "cupcake",
    "char": "🧁",
    "name": "Cupcake",
    "cat": "symbols"
  },
  {
    "code": "cupid",
    "char": "💘",
    "name": "Heart with arrow",
    "cat": "people"
  },
  {
    "code": "curacao",
    "char": "🇨🇼",
    "name": "Flag: Curaçao",
    "cat": "symbols"
  },
  {
    "code": "curling_stone",
    "char": "🥌",
    "name": "Curling stone",
    "cat": "symbols"
  },
  {
    "code": "curly_haired_man",
    "char": "👨🦱",
    "name": "Man: curly hair",
    "cat": "people"
  },
  {
    "code": "curly_haired_woman",
    "char": "👩🦱",
    "name": "Woman: curly hair",
    "cat": "people"
  },
  {
    "code": "curly_loop",
    "char": "➰",
    "name": "Curly loop",
    "cat": "symbols"
  },
  {
    "code": "currency_exchange",
    "char": "💱",
    "name": "Currency exchange",
    "cat": "symbols"
  },
  {
    "code": "curry",
    "char": "🍛",
    "name": "Curry rice",
    "cat": "symbols"
  },
  {
    "code": "cursing_face",
    "char": "🤬",
    "name": "Face with symbols on mouth",
    "cat": "people"
  },
  {
    "code": "custard",
    "char": "🍮",
    "name": "Custard",
    "cat": "symbols"
  },
  {
    "code": "customs",
    "char": "🛃",
    "name": "Customs",
    "cat": "symbols"
  },
  {
    "code": "cut_of_meat",
    "char": "🥩",
    "name": "Cut of meat",
    "cat": "symbols"
  },
  {
    "code": "cyclone",
    "char": "🌀",
    "name": "Cyclone",
    "cat": "symbols"
  },
  {
    "code": "cyprus",
    "char": "🇨🇾",
    "name": "Flag: Cyprus",
    "cat": "symbols"
  },
  {
    "code": "czech_republic",
    "char": "🇨🇿",
    "name": "Flag: Czechia",
    "cat": "symbols"
  },
  {
    "code": "dagger",
    "char": "🗡",
    "name": "Dagger",
    "cat": "tech"
  },
  {
    "code": "dancer",
    "char": "💃",
    "name": "Woman dancing",
    "cat": "people"
  },
  {
    "code": "dancers",
    "char": "👯",
    "name": "People with bunny ears",
    "cat": "people"
  },
  {
    "code": "dancing_men",
    "char": "👯♂",
    "name": "Men with bunny ears",
    "cat": "people"
  },
  {
    "code": "dancing_women",
    "char": "👯♀",
    "name": "Women with bunny ears",
    "cat": "people"
  },
  {
    "code": "dango",
    "char": "🍡",
    "name": "Dango",
    "cat": "symbols"
  },
  {
    "code": "dark_sunglasses",
    "char": "🕶",
    "name": "Sunglasses",
    "cat": "tech"
  },
  {
    "code": "dart",
    "char": "🎯",
    "name": "Bullseye",
    "cat": "symbols"
  },
  {
    "code": "dash",
    "char": "💨",
    "name": "Dashing away",
    "cat": "people"
  },
  {
    "code": "date",
    "char": "📅",
    "name": "Calendar",
    "cat": "tech"
  },
  {
    "code": "de",
    "char": "🇩🇪",
    "name": "Flag: Germany",
    "cat": "symbols"
  },
  {
    "code": "deaf_man",
    "char": "🧏♂",
    "name": "Deaf man",
    "cat": "people"
  },
  {
    "code": "deaf_person",
    "char": "🧏",
    "name": "Deaf person",
    "cat": "people"
  },
  {
    "code": "deaf_woman",
    "char": "🧏♀",
    "name": "Deaf woman",
    "cat": "people"
  },
  {
    "code": "deciduous_tree",
    "char": "🌳",
    "name": "Deciduous tree",
    "cat": "symbols"
  },
  {
    "code": "deer",
    "char": "🦌",
    "name": "Deer",
    "cat": "symbols"
  },
  {
    "code": "denmark",
    "char": "🇩🇰",
    "name": "Flag: Denmark",
    "cat": "symbols"
  },
  {
    "code": "department_store",
    "char": "🏬",
    "name": "Department store",
    "cat": "symbols"
  },
  {
    "code": "derelict_house",
    "char": "🏚",
    "name": "Derelict house",
    "cat": "symbols"
  },
  {
    "code": "desert",
    "char": "🏜",
    "name": "Desert",
    "cat": "symbols"
  },
  {
    "code": "desert_island",
    "char": "🏝",
    "name": "Desert island",
    "cat": "symbols"
  },
  {
    "code": "desktop_computer",
    "char": "🖥",
    "name": "Desktop computer",
    "cat": "tech"
  },
  {
    "code": "detective",
    "char": "🕵",
    "name": "Detective",
    "cat": "people"
  },
  {
    "code": "diamond_shape_with_a_dot_inside",
    "char": "💠",
    "name": "Diamond with a dot",
    "cat": "symbols"
  },
  {
    "code": "diamonds",
    "char": "♦",
    "name": "Diamond suit",
    "cat": "symbols"
  },
  {
    "code": "diego_garcia",
    "char": "🇩🇬",
    "name": "Flag: Diego Garcia",
    "cat": "symbols"
  },
  {
    "code": "disappointed",
    "char": "😞",
    "name": "Disappointed face",
    "cat": "people"
  },
  {
    "code": "disappointed_relieved",
    "char": "😥",
    "name": "Sad but relieved face",
    "cat": "people"
  },
  {
    "code": "disguised_face",
    "char": "🥸",
    "name": "Disguised face",
    "cat": "people"
  },
  {
    "code": "diving_mask",
    "char": "🤿",
    "name": "Diving mask",
    "cat": "symbols"
  },
  {
    "code": "diya_lamp",
    "char": "🪔",
    "name": "Diya lamp",
    "cat": "tech"
  },
  {
    "code": "dizzy",
    "char": "💫",
    "name": "Dizzy",
    "cat": "people"
  },
  {
    "code": "dizzy_face",
    "char": "😵",
    "name": "Face with crossed-out eyes",
    "cat": "people"
  },
  {
    "code": "djibouti",
    "char": "🇩🇯",
    "name": "Flag: Djibouti",
    "cat": "symbols"
  },
  {
    "code": "dna",
    "char": "🧬",
    "name": "Dna",
    "cat": "tech"
  },
  {
    "code": "do_not_litter",
    "char": "🚯",
    "name": "No littering",
    "cat": "symbols"
  },
  {
    "code": "dodo",
    "char": "🦤",
    "name": "Dodo",
    "cat": "symbols"
  },
  {
    "code": "dog",
    "char": "🐶",
    "name": "Dog face",
    "cat": "symbols"
  },
  {
    "code": "dog2",
    "char": "🐕",
    "name": "Dog",
    "cat": "symbols"
  },
  {
    "code": "dollar",
    "char": "💵",
    "name": "Dollar banknote",
    "cat": "tech"
  },
  {
    "code": "dolls",
    "char": "🎎",
    "name": "Japanese dolls",
    "cat": "symbols"
  },
  {
    "code": "dolphin",
    "char": "🐬",
    "name": "Dolphin",
    "cat": "symbols"
  },
  {
    "code": "dominica",
    "char": "🇩🇲",
    "name": "Flag: Dominica",
    "cat": "symbols"
  },
  {
    "code": "dominican_republic",
    "char": "🇩🇴",
    "name": "Flag: Dominican Republic",
    "cat": "symbols"
  },
  {
    "code": "donkey",
    "char": "🫏",
    "name": "Donkey",
    "cat": "symbols"
  },
  {
    "code": "door",
    "char": "🚪",
    "name": "Door",
    "cat": "tech"
  },
  {
    "code": "dotted_line_face",
    "char": "🫥",
    "name": "Dotted line face",
    "cat": "people"
  },
  {
    "code": "doughnut",
    "char": "🍩",
    "name": "Doughnut",
    "cat": "symbols"
  },
  {
    "code": "dove",
    "char": "🕊",
    "name": "Dove",
    "cat": "symbols"
  },
  {
    "code": "dragon",
    "char": "🐉",
    "name": "Dragon",
    "cat": "symbols"
  },
  {
    "code": "dragon_face",
    "char": "🐲",
    "name": "Dragon face",
    "cat": "symbols"
  },
  {
    "code": "dress",
    "char": "👗",
    "name": "Dress",
    "cat": "tech"
  },
  {
    "code": "dromedary_camel",
    "char": "🐪",
    "name": "Camel",
    "cat": "symbols"
  },
  {
    "code": "drooling_face",
    "char": "🤤",
    "name": "Drooling face",
    "cat": "people"
  },
  {
    "code": "drop_of_blood",
    "char": "🩸",
    "name": "Drop of blood",
    "cat": "tech"
  },
  {
    "code": "droplet",
    "char": "💧",
    "name": "Droplet",
    "cat": "symbols"
  },
  {
    "code": "drum",
    "char": "🥁",
    "name": "Drum",
    "cat": "tech"
  },
  {
    "code": "duck",
    "char": "🦆",
    "name": "Duck",
    "cat": "symbols"
  },
  {
    "code": "dumpling",
    "char": "🥟",
    "name": "Dumpling",
    "cat": "symbols"
  },
  {
    "code": "dvd",
    "char": "📀",
    "name": "Dvd",
    "cat": "tech"
  },
  {
    "code": "e-mail",
    "char": "📧",
    "name": "E-mail",
    "cat": "tech"
  },
  {
    "code": "eagle",
    "char": "🦅",
    "name": "Eagle",
    "cat": "symbols"
  },
  {
    "code": "ear",
    "char": "👂",
    "name": "Ear",
    "cat": "people"
  },
  {
    "code": "ear_of_rice",
    "char": "🌾",
    "name": "Sheaf of rice",
    "cat": "symbols"
  },
  {
    "code": "ear_with_hearing_aid",
    "char": "🦻",
    "name": "Ear with hearing aid",
    "cat": "people"
  },
  {
    "code": "earth_africa",
    "char": "🌍",
    "name": "Globe showing Europe-Africa",
    "cat": "symbols"
  },
  {
    "code": "earth_americas",
    "char": "🌎",
    "name": "Globe showing Americas",
    "cat": "symbols"
  },
  {
    "code": "earth_asia",
    "char": "🌏",
    "name": "Globe showing Asia-Australia",
    "cat": "symbols"
  },
  {
    "code": "ecuador",
    "char": "🇪🇨",
    "name": "Flag: Ecuador",
    "cat": "symbols"
  },
  {
    "code": "egg",
    "char": "🥚",
    "name": "Egg",
    "cat": "symbols"
  },
  {
    "code": "eggplant",
    "char": "🍆",
    "name": "Eggplant",
    "cat": "symbols"
  },
  {
    "code": "egypt",
    "char": "🇪🇬",
    "name": "Flag: Egypt",
    "cat": "symbols"
  },
  {
    "code": "eight",
    "char": "8⃣",
    "name": "Keycap: 8",
    "cat": "symbols"
  },
  {
    "code": "eight_pointed_black_star",
    "char": "✴",
    "name": "Eight-pointed star",
    "cat": "symbols"
  },
  {
    "code": "eight_spoked_asterisk",
    "char": "✳",
    "name": "Eight-spoked asterisk",
    "cat": "symbols"
  },
  {
    "code": "eject_button",
    "char": "⏏",
    "name": "Eject button",
    "cat": "symbols"
  },
  {
    "code": "el_salvador",
    "char": "🇸🇻",
    "name": "Flag: El Salvador",
    "cat": "symbols"
  },
  {
    "code": "electric_plug",
    "char": "🔌",
    "name": "Electric plug",
    "cat": "tech"
  },
  {
    "code": "elephant",
    "char": "🐘",
    "name": "Elephant",
    "cat": "symbols"
  },
  {
    "code": "elevator",
    "char": "🛗",
    "name": "Elevator",
    "cat": "tech"
  },
  {
    "code": "elf",
    "char": "🧝",
    "name": "Elf",
    "cat": "people"
  },
  {
    "code": "elf_man",
    "char": "🧝♂",
    "name": "Man elf",
    "cat": "people"
  },
  {
    "code": "elf_woman",
    "char": "🧝♀",
    "name": "Woman elf",
    "cat": "people"
  },
  {
    "code": "email",
    "char": "📧",
    "name": "E-mail",
    "cat": "tech"
  },
  {
    "code": "empty_nest",
    "char": "🪹",
    "name": "Empty nest",
    "cat": "symbols"
  },
  {
    "code": "end",
    "char": "🔚",
    "name": "END arrow",
    "cat": "symbols"
  },
  {
    "code": "england",
    "char": "🏴󠁧󠁢󠁥󠁮󠁧󠁿",
    "name": "Flag: England",
    "cat": "symbols"
  },
  {
    "code": "envelope",
    "char": "✉",
    "name": "Envelope",
    "cat": "tech"
  },
  {
    "code": "envelope_with_arrow",
    "char": "📩",
    "name": "Envelope with arrow",
    "cat": "tech"
  },
  {
    "code": "equatorial_guinea",
    "char": "🇬🇶",
    "name": "Flag: Equatorial Guinea",
    "cat": "symbols"
  },
  {
    "code": "eritrea",
    "char": "🇪🇷",
    "name": "Flag: Eritrea",
    "cat": "symbols"
  },
  {
    "code": "es",
    "char": "🇪🇸",
    "name": "Flag: Spain",
    "cat": "symbols"
  },
  {
    "code": "estonia",
    "char": "🇪🇪",
    "name": "Flag: Estonia",
    "cat": "symbols"
  },
  {
    "code": "ethiopia",
    "char": "🇪🇹",
    "name": "Flag: Ethiopia",
    "cat": "symbols"
  },
  {
    "code": "eu",
    "char": "🇪🇺",
    "name": "Flag: European Union",
    "cat": "symbols"
  },
  {
    "code": "euro",
    "char": "💶",
    "name": "Euro banknote",
    "cat": "tech"
  },
  {
    "code": "european_castle",
    "char": "🏰",
    "name": "Castle",
    "cat": "symbols"
  },
  {
    "code": "european_post_office",
    "char": "🏤",
    "name": "Post office",
    "cat": "symbols"
  },
  {
    "code": "european_union",
    "char": "🇪🇺",
    "name": "Flag: European Union",
    "cat": "symbols"
  },
  {
    "code": "evergreen_tree",
    "char": "🌲",
    "name": "Evergreen tree",
    "cat": "symbols"
  },
  {
    "code": "exclamation",
    "char": "❗",
    "name": "Red exclamation mark",
    "cat": "status"
  },
  {
    "code": "expressionless",
    "char": "😑",
    "name": "Expressionless face",
    "cat": "people"
  },
  {
    "code": "eye",
    "char": "👁",
    "name": "Eye",
    "cat": "people"
  },
  {
    "code": "eye_speech_bubble",
    "char": "👁🗨",
    "name": "Eye in speech bubble",
    "cat": "people"
  },
  {
    "code": "eyeglasses",
    "char": "👓",
    "name": "Glasses",
    "cat": "tech"
  },
  {
    "code": "face_exhaling",
    "char": "😮💨",
    "name": "Face exhaling",
    "cat": "people"
  },
  {
    "code": "face_holding_back_tears",
    "char": "🥹",
    "name": "Face holding back tears",
    "cat": "people"
  },
  {
    "code": "face_in_clouds",
    "char": "😶🌫",
    "name": "Face in clouds",
    "cat": "people"
  },
  {
    "code": "face_with_diagonal_mouth",
    "char": "🫤",
    "name": "Face with diagonal mouth",
    "cat": "people"
  },
  {
    "code": "face_with_head_bandage",
    "char": "🤕",
    "name": "Face with head-bandage",
    "cat": "people"
  },
  {
    "code": "face_with_open_eyes_and_hand_over_mouth",
    "char": "🫢",
    "name": "Face with open eyes and hand over mouth",
    "cat": "people"
  },
  {
    "code": "face_with_peeking_eye",
    "char": "🫣",
    "name": "Face with peeking eye",
    "cat": "people"
  },
  {
    "code": "face_with_spiral_eyes",
    "char": "😵💫",
    "name": "Face with spiral eyes",
    "cat": "people"
  },
  {
    "code": "face_with_thermometer",
    "char": "🤒",
    "name": "Face with thermometer",
    "cat": "people"
  },
  {
    "code": "facepunch",
    "char": "👊",
    "name": "Oncoming fist",
    "cat": "people"
  },
  {
    "code": "factory",
    "char": "🏭",
    "name": "Factory",
    "cat": "symbols"
  },
  {
    "code": "factory_worker",
    "char": "🧑🏭",
    "name": "Factory worker",
    "cat": "people"
  },
  {
    "code": "fairy",
    "char": "🧚",
    "name": "Fairy",
    "cat": "people"
  },
  {
    "code": "fairy_man",
    "char": "🧚♂",
    "name": "Man fairy",
    "cat": "people"
  },
  {
    "code": "fairy_woman",
    "char": "🧚♀",
    "name": "Woman fairy",
    "cat": "people"
  },
  {
    "code": "falafel",
    "char": "🧆",
    "name": "Falafel",
    "cat": "symbols"
  },
  {
    "code": "falkland_islands",
    "char": "🇫🇰",
    "name": "Flag: Falkland Islands",
    "cat": "symbols"
  },
  {
    "code": "fallen_leaf",
    "char": "🍂",
    "name": "Fallen leaf",
    "cat": "symbols"
  },
  {
    "code": "family",
    "char": "👪",
    "name": "Family",
    "cat": "people"
  },
  {
    "code": "family_man_boy",
    "char": "👨👦",
    "name": "Family: man, boy",
    "cat": "people"
  },
  {
    "code": "family_man_boy_boy",
    "char": "👨👦👦",
    "name": "Family: man, boy, boy",
    "cat": "people"
  },
  {
    "code": "family_man_girl",
    "char": "👨👧",
    "name": "Family: man, girl",
    "cat": "people"
  },
  {
    "code": "family_man_girl_boy",
    "char": "👨👧👦",
    "name": "Family: man, girl, boy",
    "cat": "people"
  },
  {
    "code": "family_man_girl_girl",
    "char": "👨👧👧",
    "name": "Family: man, girl, girl",
    "cat": "people"
  },
  {
    "code": "family_man_man_boy",
    "char": "👨👨👦",
    "name": "Family: man, man, boy",
    "cat": "people"
  },
  {
    "code": "family_man_man_boy_boy",
    "char": "👨👨👦👦",
    "name": "Family: man, man, boy, boy",
    "cat": "people"
  },
  {
    "code": "family_man_man_girl",
    "char": "👨👨👧",
    "name": "Family: man, man, girl",
    "cat": "people"
  },
  {
    "code": "family_man_man_girl_boy",
    "char": "👨👨👧👦",
    "name": "Family: man, man, girl, boy",
    "cat": "people"
  },
  {
    "code": "family_man_man_girl_girl",
    "char": "👨👨👧👧",
    "name": "Family: man, man, girl, girl",
    "cat": "people"
  },
  {
    "code": "family_man_woman_boy",
    "char": "👨👩👦",
    "name": "Family: man, woman, boy",
    "cat": "people"
  },
  {
    "code": "family_man_woman_boy_boy",
    "char": "👨👩👦👦",
    "name": "Family: man, woman, boy, boy",
    "cat": "people"
  },
  {
    "code": "family_man_woman_girl",
    "char": "👨👩👧",
    "name": "Family: man, woman, girl",
    "cat": "people"
  },
  {
    "code": "family_man_woman_girl_boy",
    "char": "👨👩👧👦",
    "name": "Family: man, woman, girl, boy",
    "cat": "people"
  },
  {
    "code": "family_man_woman_girl_girl",
    "char": "👨👩👧👧",
    "name": "Family: man, woman, girl, girl",
    "cat": "people"
  },
  {
    "code": "family_woman_boy",
    "char": "👩👦",
    "name": "Family: woman, boy",
    "cat": "people"
  },
  {
    "code": "family_woman_boy_boy",
    "char": "👩👦👦",
    "name": "Family: woman, boy, boy",
    "cat": "people"
  },
  {
    "code": "family_woman_girl",
    "char": "👩👧",
    "name": "Family: woman, girl",
    "cat": "people"
  },
  {
    "code": "family_woman_girl_boy",
    "char": "👩👧👦",
    "name": "Family: woman, girl, boy",
    "cat": "people"
  },
  {
    "code": "family_woman_girl_girl",
    "char": "👩👧👧",
    "name": "Family: woman, girl, girl",
    "cat": "people"
  },
  {
    "code": "family_woman_woman_boy",
    "char": "👩👩👦",
    "name": "Family: woman, woman, boy",
    "cat": "people"
  },
  {
    "code": "family_woman_woman_boy_boy",
    "char": "👩👩👦👦",
    "name": "Family: woman, woman, boy, boy",
    "cat": "people"
  },
  {
    "code": "family_woman_woman_girl",
    "char": "👩👩👧",
    "name": "Family: woman, woman, girl",
    "cat": "people"
  },
  {
    "code": "family_woman_woman_girl_boy",
    "char": "👩👩👧👦",
    "name": "Family: woman, woman, girl, boy",
    "cat": "people"
  },
  {
    "code": "family_woman_woman_girl_girl",
    "char": "👩👩👧👧",
    "name": "Family: woman, woman, girl, girl",
    "cat": "people"
  },
  {
    "code": "farmer",
    "char": "🧑🌾",
    "name": "Farmer",
    "cat": "people"
  },
  {
    "code": "faroe_islands",
    "char": "🇫🇴",
    "name": "Flag: Faroe Islands",
    "cat": "symbols"
  },
  {
    "code": "fast_forward",
    "char": "⏩",
    "name": "Fast-forward button",
    "cat": "symbols"
  },
  {
    "code": "fax",
    "char": "📠",
    "name": "Fax machine",
    "cat": "tech"
  },
  {
    "code": "fearful",
    "char": "😨",
    "name": "Fearful face",
    "cat": "people"
  },
  {
    "code": "feather",
    "char": "🪶",
    "name": "Feather",
    "cat": "symbols"
  },
  {
    "code": "feet",
    "char": "🐾",
    "name": "Paw prints",
    "cat": "symbols"
  },
  {
    "code": "female_detective",
    "char": "🕵♀",
    "name": "Woman detective",
    "cat": "people"
  },
  {
    "code": "female_sign",
    "char": "♀",
    "name": "Female sign",
    "cat": "symbols"
  },
  {
    "code": "ferris_wheel",
    "char": "🎡",
    "name": "Ferris wheel",
    "cat": "symbols"
  },
  {
    "code": "ferry",
    "char": "⛴",
    "name": "Ferry",
    "cat": "symbols"
  },
  {
    "code": "field_hockey",
    "char": "🏑",
    "name": "Field hockey",
    "cat": "symbols"
  },
  {
    "code": "fiji",
    "char": "🇫🇯",
    "name": "Flag: Fiji",
    "cat": "symbols"
  },
  {
    "code": "file_cabinet",
    "char": "🗄",
    "name": "File cabinet",
    "cat": "tech"
  },
  {
    "code": "file_folder",
    "char": "📁",
    "name": "File folder",
    "cat": "tech"
  },
  {
    "code": "film_projector",
    "char": "📽",
    "name": "Film projector",
    "cat": "tech"
  },
  {
    "code": "film_strip",
    "char": "🎞",
    "name": "Film frames",
    "cat": "tech"
  },
  {
    "code": "finland",
    "char": "🇫🇮",
    "name": "Flag: Finland",
    "cat": "symbols"
  },
  {
    "code": "fire_engine",
    "char": "🚒",
    "name": "Fire engine",
    "cat": "symbols"
  },
  {
    "code": "fire_extinguisher",
    "char": "🧯",
    "name": "Fire extinguisher",
    "cat": "tech"
  },
  {
    "code": "firecracker",
    "char": "🧨",
    "name": "Firecracker",
    "cat": "symbols"
  },
  {
    "code": "firefighter",
    "char": "🧑🚒",
    "name": "Firefighter",
    "cat": "people"
  },
  {
    "code": "fireworks",
    "char": "🎆",
    "name": "Fireworks",
    "cat": "symbols"
  },
  {
    "code": "first_quarter_moon",
    "char": "🌓",
    "name": "First quarter moon",
    "cat": "symbols"
  },
  {
    "code": "first_quarter_moon_with_face",
    "char": "🌛",
    "name": "First quarter moon face",
    "cat": "symbols"
  },
  {
    "code": "fish",
    "char": "🐟",
    "name": "Fish",
    "cat": "symbols"
  },
  {
    "code": "fish_cake",
    "char": "🍥",
    "name": "Fish cake with swirl",
    "cat": "symbols"
  },
  {
    "code": "fishing_pole_and_fish",
    "char": "🎣",
    "name": "Fishing pole",
    "cat": "symbols"
  },
  {
    "code": "fist",
    "char": "✊",
    "name": "Raised fist",
    "cat": "people"
  },
  {
    "code": "fist_left",
    "char": "🤛",
    "name": "Left-facing fist",
    "cat": "people"
  },
  {
    "code": "fist_oncoming",
    "char": "👊",
    "name": "Oncoming fist",
    "cat": "people"
  },
  {
    "code": "fist_raised",
    "char": "✊",
    "name": "Raised fist",
    "cat": "people"
  },
  {
    "code": "fist_right",
    "char": "🤜",
    "name": "Right-facing fist",
    "cat": "people"
  },
  {
    "code": "five",
    "char": "5⃣",
    "name": "Keycap: 5",
    "cat": "symbols"
  },
  {
    "code": "flags",
    "char": "🎏",
    "name": "Carp streamer",
    "cat": "symbols"
  },
  {
    "code": "flamingo",
    "char": "🦩",
    "name": "Flamingo",
    "cat": "symbols"
  },
  {
    "code": "flashlight",
    "char": "🔦",
    "name": "Flashlight",
    "cat": "tech"
  },
  {
    "code": "flat_shoe",
    "char": "🥿",
    "name": "Flat shoe",
    "cat": "tech"
  },
  {
    "code": "flatbread",
    "char": "🫓",
    "name": "Flatbread",
    "cat": "symbols"
  },
  {
    "code": "fleur_de_lis",
    "char": "⚜",
    "name": "Fleur-de-lis",
    "cat": "symbols"
  },
  {
    "code": "flight_arrival",
    "char": "🛬",
    "name": "Airplane arrival",
    "cat": "symbols"
  },
  {
    "code": "flight_departure",
    "char": "🛫",
    "name": "Airplane departure",
    "cat": "symbols"
  },
  {
    "code": "flipper",
    "char": "🐬",
    "name": "Dolphin",
    "cat": "symbols"
  },
  {
    "code": "floppy_disk",
    "char": "💾",
    "name": "Floppy disk",
    "cat": "tech"
  },
  {
    "code": "flower_playing_cards",
    "char": "🎴",
    "name": "Flower playing cards",
    "cat": "symbols"
  },
  {
    "code": "flushed",
    "char": "😳",
    "name": "Flushed face",
    "cat": "people"
  },
  {
    "code": "flute",
    "char": "🪈",
    "name": "Flute",
    "cat": "tech"
  },
  {
    "code": "fly",
    "char": "🪰",
    "name": "Fly",
    "cat": "symbols"
  },
  {
    "code": "flying_disc",
    "char": "🥏",
    "name": "Flying disc",
    "cat": "symbols"
  },
  {
    "code": "flying_saucer",
    "char": "🛸",
    "name": "Flying saucer",
    "cat": "symbols"
  },
  {
    "code": "fog",
    "char": "🌫",
    "name": "Fog",
    "cat": "symbols"
  },
  {
    "code": "foggy",
    "char": "🌁",
    "name": "Foggy",
    "cat": "symbols"
  },
  {
    "code": "folding_hand_fan",
    "char": "🪭",
    "name": "Folding hand fan",
    "cat": "tech"
  },
  {
    "code": "fondue",
    "char": "🫕",
    "name": "Fondue",
    "cat": "symbols"
  },
  {
    "code": "foot",
    "char": "🦶",
    "name": "Foot",
    "cat": "people"
  },
  {
    "code": "football",
    "char": "🏈",
    "name": "American football",
    "cat": "symbols"
  },
  {
    "code": "footprints",
    "char": "👣",
    "name": "Footprints",
    "cat": "people"
  },
  {
    "code": "fork_and_knife",
    "char": "🍴",
    "name": "Fork and knife",
    "cat": "symbols"
  },
  {
    "code": "fortune_cookie",
    "char": "🥠",
    "name": "Fortune cookie",
    "cat": "symbols"
  },
  {
    "code": "fountain",
    "char": "⛲",
    "name": "Fountain",
    "cat": "symbols"
  },
  {
    "code": "fountain_pen",
    "char": "🖋",
    "name": "Fountain pen",
    "cat": "tech"
  },
  {
    "code": "four",
    "char": "4⃣",
    "name": "Keycap: 4",
    "cat": "symbols"
  },
  {
    "code": "four_leaf_clover",
    "char": "🍀",
    "name": "Four leaf clover",
    "cat": "symbols"
  },
  {
    "code": "fox_face",
    "char": "🦊",
    "name": "Fox",
    "cat": "symbols"
  },
  {
    "code": "fr",
    "char": "🇫🇷",
    "name": "Flag: France",
    "cat": "symbols"
  },
  {
    "code": "framed_picture",
    "char": "🖼",
    "name": "Framed picture",
    "cat": "symbols"
  },
  {
    "code": "free",
    "char": "🆓",
    "name": "FREE button",
    "cat": "symbols"
  },
  {
    "code": "french_guiana",
    "char": "🇬🇫",
    "name": "Flag: French Guiana",
    "cat": "symbols"
  },
  {
    "code": "french_polynesia",
    "char": "🇵🇫",
    "name": "Flag: French Polynesia",
    "cat": "symbols"
  },
  {
    "code": "french_southern_territories",
    "char": "🇹🇫",
    "name": "Flag: French Southern Territories",
    "cat": "symbols"
  },
  {
    "code": "fried_egg",
    "char": "🍳",
    "name": "Cooking",
    "cat": "symbols"
  },
  {
    "code": "fried_shrimp",
    "char": "🍤",
    "name": "Fried shrimp",
    "cat": "symbols"
  },
  {
    "code": "fries",
    "char": "🍟",
    "name": "French fries",
    "cat": "symbols"
  },
  {
    "code": "frog",
    "char": "🐸",
    "name": "Frog",
    "cat": "symbols"
  },
  {
    "code": "frowning",
    "char": "😦",
    "name": "Frowning face with open mouth",
    "cat": "people"
  },
  {
    "code": "frowning_face",
    "char": "☹",
    "name": "Frowning face",
    "cat": "people"
  },
  {
    "code": "frowning_man",
    "char": "🙍♂",
    "name": "Man frowning",
    "cat": "people"
  },
  {
    "code": "frowning_person",
    "char": "🙍",
    "name": "Person frowning",
    "cat": "people"
  },
  {
    "code": "frowning_woman",
    "char": "🙍♀",
    "name": "Woman frowning",
    "cat": "people"
  },
  {
    "code": "fu",
    "char": "🖕",
    "name": "Middle finger",
    "cat": "people"
  },
  {
    "code": "fuelpump",
    "char": "⛽",
    "name": "Fuel pump",
    "cat": "symbols"
  },
  {
    "code": "full_moon",
    "char": "🌕",
    "name": "Full moon",
    "cat": "symbols"
  },
  {
    "code": "full_moon_with_face",
    "char": "🌝",
    "name": "Full moon face",
    "cat": "symbols"
  },
  {
    "code": "funeral_urn",
    "char": "⚱",
    "name": "Funeral urn",
    "cat": "tech"
  },
  {
    "code": "gabon",
    "char": "🇬🇦",
    "name": "Flag: Gabon",
    "cat": "symbols"
  },
  {
    "code": "gambia",
    "char": "🇬🇲",
    "name": "Flag: Gambia",
    "cat": "symbols"
  },
  {
    "code": "game_die",
    "char": "🎲",
    "name": "Game die",
    "cat": "symbols"
  },
  {
    "code": "garlic",
    "char": "🧄",
    "name": "Garlic",
    "cat": "symbols"
  },
  {
    "code": "gb",
    "char": "🇬🇧",
    "name": "Flag: United Kingdom",
    "cat": "symbols"
  },
  {
    "code": "gem",
    "char": "💎",
    "name": "Gem stone",
    "cat": "tech"
  },
  {
    "code": "gemini",
    "char": "♊",
    "name": "Gemini",
    "cat": "symbols"
  },
  {
    "code": "genie",
    "char": "🧞",
    "name": "Genie",
    "cat": "people"
  },
  {
    "code": "genie_man",
    "char": "🧞♂",
    "name": "Man genie",
    "cat": "people"
  },
  {
    "code": "genie_woman",
    "char": "🧞♀",
    "name": "Woman genie",
    "cat": "people"
  },
  {
    "code": "georgia",
    "char": "🇬🇪",
    "name": "Flag: Georgia",
    "cat": "symbols"
  },
  {
    "code": "ghana",
    "char": "🇬🇭",
    "name": "Flag: Ghana",
    "cat": "symbols"
  },
  {
    "code": "ghost",
    "char": "👻",
    "name": "Ghost",
    "cat": "people"
  },
  {
    "code": "gibraltar",
    "char": "🇬🇮",
    "name": "Flag: Gibraltar",
    "cat": "symbols"
  },
  {
    "code": "gift",
    "char": "🎁",
    "name": "Wrapped gift",
    "cat": "symbols"
  },
  {
    "code": "gift_heart",
    "char": "💝",
    "name": "Heart with ribbon",
    "cat": "people"
  },
  {
    "code": "ginger_root",
    "char": "🫚",
    "name": "Ginger root",
    "cat": "symbols"
  },
  {
    "code": "giraffe",
    "char": "🦒",
    "name": "Giraffe",
    "cat": "symbols"
  },
  {
    "code": "girl",
    "char": "👧",
    "name": "Girl",
    "cat": "people"
  },
  {
    "code": "globe_with_meridians",
    "char": "🌐",
    "name": "Globe with meridians",
    "cat": "tech"
  },
  {
    "code": "gloves",
    "char": "🧤",
    "name": "Gloves",
    "cat": "tech"
  },
  {
    "code": "goal_net",
    "char": "🥅",
    "name": "Goal net",
    "cat": "symbols"
  },
  {
    "code": "goat",
    "char": "🐐",
    "name": "Goat",
    "cat": "symbols"
  },
  {
    "code": "goggles",
    "char": "🥽",
    "name": "Goggles",
    "cat": "tech"
  },
  {
    "code": "golf",
    "char": "⛳",
    "name": "Flag in hole",
    "cat": "symbols"
  },
  {
    "code": "golfing",
    "char": "🏌",
    "name": "Person golfing",
    "cat": "people"
  },
  {
    "code": "golfing_man",
    "char": "🏌♂",
    "name": "Man golfing",
    "cat": "people"
  },
  {
    "code": "golfing_woman",
    "char": "🏌♀",
    "name": "Woman golfing",
    "cat": "people"
  },
  {
    "code": "goose",
    "char": "🪿",
    "name": "Goose",
    "cat": "symbols"
  },
  {
    "code": "gorilla",
    "char": "🦍",
    "name": "Gorilla",
    "cat": "symbols"
  },
  {
    "code": "grapes",
    "char": "🍇",
    "name": "Grapes",
    "cat": "symbols"
  },
  {
    "code": "greece",
    "char": "🇬🇷",
    "name": "Flag: Greece",
    "cat": "symbols"
  },
  {
    "code": "green_apple",
    "char": "🍏",
    "name": "Green apple",
    "cat": "symbols"
  },
  {
    "code": "green_book",
    "char": "📗",
    "name": "Green book",
    "cat": "tech"
  },
  {
    "code": "green_circle",
    "char": "🟢",
    "name": "Green circle",
    "cat": "status"
  },
  {
    "code": "green_heart",
    "char": "💚",
    "name": "Green heart",
    "cat": "people"
  },
  {
    "code": "green_salad",
    "char": "🥗",
    "name": "Green salad",
    "cat": "symbols"
  },
  {
    "code": "green_square",
    "char": "🟩",
    "name": "Green square",
    "cat": "symbols"
  },
  {
    "code": "greenland",
    "char": "🇬🇱",
    "name": "Flag: Greenland",
    "cat": "symbols"
  },
  {
    "code": "grenada",
    "char": "🇬🇩",
    "name": "Flag: Grenada",
    "cat": "symbols"
  },
  {
    "code": "grey_exclamation",
    "char": "❕",
    "name": "White exclamation mark",
    "cat": "status"
  },
  {
    "code": "grey_heart",
    "char": "🩶",
    "name": "Grey heart",
    "cat": "people"
  },
  {
    "code": "grey_question",
    "char": "❔",
    "name": "White question mark",
    "cat": "status"
  },
  {
    "code": "grimacing",
    "char": "😬",
    "name": "Grimacing face",
    "cat": "people"
  },
  {
    "code": "grinning",
    "char": "😀",
    "name": "Grinning face",
    "cat": "people"
  },
  {
    "code": "guadeloupe",
    "char": "🇬🇵",
    "name": "Flag: Guadeloupe",
    "cat": "symbols"
  },
  {
    "code": "guam",
    "char": "🇬🇺",
    "name": "Flag: Guam",
    "cat": "symbols"
  },
  {
    "code": "guard",
    "char": "💂",
    "name": "Guard",
    "cat": "people"
  },
  {
    "code": "guardsman",
    "char": "💂♂",
    "name": "Man guard",
    "cat": "people"
  },
  {
    "code": "guardswoman",
    "char": "💂♀",
    "name": "Woman guard",
    "cat": "people"
  },
  {
    "code": "guatemala",
    "char": "🇬🇹",
    "name": "Flag: Guatemala",
    "cat": "symbols"
  },
  {
    "code": "guernsey",
    "char": "🇬🇬",
    "name": "Flag: Guernsey",
    "cat": "symbols"
  },
  {
    "code": "guide_dog",
    "char": "🦮",
    "name": "Guide dog",
    "cat": "symbols"
  },
  {
    "code": "guinea",
    "char": "🇬🇳",
    "name": "Flag: Guinea",
    "cat": "symbols"
  },
  {
    "code": "guinea_bissau",
    "char": "🇬🇼",
    "name": "Flag: Guinea-Bissau",
    "cat": "symbols"
  },
  {
    "code": "guitar",
    "char": "🎸",
    "name": "Guitar",
    "cat": "tech"
  },
  {
    "code": "gun",
    "char": "🔫",
    "name": "Water pistol",
    "cat": "symbols"
  },
  {
    "code": "guyana",
    "char": "🇬🇾",
    "name": "Flag: Guyana",
    "cat": "symbols"
  },
  {
    "code": "hair_pick",
    "char": "🪮",
    "name": "Hair pick",
    "cat": "tech"
  },
  {
    "code": "haircut",
    "char": "💇",
    "name": "Person getting haircut",
    "cat": "people"
  },
  {
    "code": "haircut_man",
    "char": "💇♂",
    "name": "Man getting haircut",
    "cat": "people"
  },
  {
    "code": "haircut_woman",
    "char": "💇♀",
    "name": "Woman getting haircut",
    "cat": "people"
  },
  {
    "code": "haiti",
    "char": "🇭🇹",
    "name": "Flag: Haiti",
    "cat": "symbols"
  },
  {
    "code": "hamburger",
    "char": "🍔",
    "name": "Hamburger",
    "cat": "symbols"
  },
  {
    "code": "hammer",
    "char": "🔨",
    "name": "Hammer",
    "cat": "tech"
  },
  {
    "code": "hammer_and_pick",
    "char": "⚒",
    "name": "Hammer and pick",
    "cat": "tech"
  },
  {
    "code": "hammer_and_wrench",
    "char": "🛠",
    "name": "Hammer and wrench",
    "cat": "tech"
  },
  {
    "code": "hamsa",
    "char": "🪬",
    "name": "Hamsa",
    "cat": "tech"
  },
  {
    "code": "hamster",
    "char": "🐹",
    "name": "Hamster",
    "cat": "symbols"
  },
  {
    "code": "hand",
    "char": "✋",
    "name": "Raised hand",
    "cat": "people"
  },
  {
    "code": "hand_over_mouth",
    "char": "🤭",
    "name": "Face with hand over mouth",
    "cat": "people"
  },
  {
    "code": "hand_with_index_finger_and_thumb_crossed",
    "char": "🫰",
    "name": "Hand with index finger and thumb crossed",
    "cat": "people"
  },
  {
    "code": "handbag",
    "char": "👜",
    "name": "Handbag",
    "cat": "tech"
  },
  {
    "code": "handball_person",
    "char": "🤾",
    "name": "Person playing handball",
    "cat": "people"
  },
  {
    "code": "handshake",
    "char": "🤝",
    "name": "Handshake",
    "cat": "people"
  },
  {
    "code": "hankey",
    "char": "💩",
    "name": "Pile of poo",
    "cat": "people"
  },
  {
    "code": "hash",
    "char": "#⃣",
    "name": "Keycap: #",
    "cat": "symbols"
  },
  {
    "code": "hatched_chick",
    "char": "🐥",
    "name": "Front-facing baby chick",
    "cat": "symbols"
  },
  {
    "code": "hatching_chick",
    "char": "🐣",
    "name": "Hatching chick",
    "cat": "symbols"
  },
  {
    "code": "headphones",
    "char": "🎧",
    "name": "Headphone",
    "cat": "tech"
  },
  {
    "code": "headstone",
    "char": "🪦",
    "name": "Headstone",
    "cat": "tech"
  },
  {
    "code": "health_worker",
    "char": "🧑⚕",
    "name": "Health worker",
    "cat": "people"
  },
  {
    "code": "hear_no_evil",
    "char": "🙉",
    "name": "Hear-no-evil monkey",
    "cat": "people"
  },
  {
    "code": "heard_mcdonald_islands",
    "char": "🇭🇲",
    "name": "Flag: Heard & McDonald Islands",
    "cat": "symbols"
  },
  {
    "code": "heart_decoration",
    "char": "💟",
    "name": "Heart decoration",
    "cat": "people"
  },
  {
    "code": "heart_eyes",
    "char": "😍",
    "name": "Smiling face with heart-eyes",
    "cat": "people"
  },
  {
    "code": "heart_eyes_cat",
    "char": "😻",
    "name": "Smiling cat with heart-eyes",
    "cat": "people"
  },
  {
    "code": "heart_hands",
    "char": "🫶",
    "name": "Heart hands",
    "cat": "people"
  },
  {
    "code": "heart_on_fire",
    "char": "❤🔥",
    "name": "Heart on fire",
    "cat": "people"
  },
  {
    "code": "heartbeat",
    "char": "💓",
    "name": "Beating heart",
    "cat": "people"
  },
  {
    "code": "heartpulse",
    "char": "💗",
    "name": "Growing heart",
    "cat": "people"
  },
  {
    "code": "hearts",
    "char": "♥",
    "name": "Heart suit",
    "cat": "symbols"
  },
  {
    "code": "heavy_division_sign",
    "char": "➗",
    "name": "Divide",
    "cat": "symbols"
  },
  {
    "code": "heavy_dollar_sign",
    "char": "💲",
    "name": "Heavy dollar sign",
    "cat": "symbols"
  },
  {
    "code": "heavy_equals_sign",
    "char": "🟰",
    "name": "Heavy equals sign",
    "cat": "symbols"
  },
  {
    "code": "heavy_exclamation_mark",
    "char": "❗",
    "name": "Red exclamation mark",
    "cat": "symbols"
  },
  {
    "code": "heavy_heart_exclamation",
    "char": "❣",
    "name": "Heart exclamation",
    "cat": "people"
  },
  {
    "code": "heavy_minus_sign",
    "char": "➖",
    "name": "Minus",
    "cat": "symbols"
  },
  {
    "code": "heavy_multiplication_x",
    "char": "✖",
    "name": "Multiply",
    "cat": "symbols"
  },
  {
    "code": "heavy_plus_sign",
    "char": "➕",
    "name": "Plus",
    "cat": "symbols"
  },
  {
    "code": "hedgehog",
    "char": "🦔",
    "name": "Hedgehog",
    "cat": "symbols"
  },
  {
    "code": "helicopter",
    "char": "🚁",
    "name": "Helicopter",
    "cat": "symbols"
  },
  {
    "code": "herb",
    "char": "🌿",
    "name": "Herb",
    "cat": "symbols"
  },
  {
    "code": "hibiscus",
    "char": "🌺",
    "name": "Hibiscus",
    "cat": "symbols"
  },
  {
    "code": "high_brightness",
    "char": "🔆",
    "name": "Bright button",
    "cat": "symbols"
  },
  {
    "code": "high_heel",
    "char": "👠",
    "name": "High-heeled shoe",
    "cat": "tech"
  },
  {
    "code": "hiking_boot",
    "char": "🥾",
    "name": "Hiking boot",
    "cat": "tech"
  },
  {
    "code": "hindu_temple",
    "char": "🛕",
    "name": "Hindu temple",
    "cat": "symbols"
  },
  {
    "code": "hippopotamus",
    "char": "🦛",
    "name": "Hippopotamus",
    "cat": "symbols"
  },
  {
    "code": "hocho",
    "char": "🔪",
    "name": "Kitchen knife",
    "cat": "symbols"
  },
  {
    "code": "hole",
    "char": "🕳",
    "name": "Hole",
    "cat": "people"
  },
  {
    "code": "honduras",
    "char": "🇭🇳",
    "name": "Flag: Honduras",
    "cat": "symbols"
  },
  {
    "code": "honey_pot",
    "char": "🍯",
    "name": "Honey pot",
    "cat": "symbols"
  },
  {
    "code": "honeybee",
    "char": "🐝",
    "name": "Honeybee",
    "cat": "symbols"
  },
  {
    "code": "hong_kong",
    "char": "🇭🇰",
    "name": "Flag: Hong Kong SAR China",
    "cat": "symbols"
  },
  {
    "code": "hook",
    "char": "🪝",
    "name": "Hook",
    "cat": "tech"
  },
  {
    "code": "horse",
    "char": "🐴",
    "name": "Horse face",
    "cat": "symbols"
  },
  {
    "code": "horse_racing",
    "char": "🏇",
    "name": "Horse racing",
    "cat": "people"
  },
  {
    "code": "hospital",
    "char": "🏥",
    "name": "Hospital",
    "cat": "symbols"
  },
  {
    "code": "hot_face",
    "char": "🥵",
    "name": "Hot face",
    "cat": "people"
  },
  {
    "code": "hot_pepper",
    "char": "🌶",
    "name": "Hot pepper",
    "cat": "symbols"
  },
  {
    "code": "hotdog",
    "char": "🌭",
    "name": "Hot dog",
    "cat": "symbols"
  },
  {
    "code": "hotel",
    "char": "🏨",
    "name": "Hotel",
    "cat": "symbols"
  },
  {
    "code": "hotsprings",
    "char": "♨",
    "name": "Hot springs",
    "cat": "symbols"
  },
  {
    "code": "hourglass",
    "char": "⌛",
    "name": "Hourglass done",
    "cat": "status"
  },
  {
    "code": "hourglass_flowing_sand",
    "char": "⏳",
    "name": "Hourglass not done",
    "cat": "status"
  },
  {
    "code": "house",
    "char": "🏠",
    "name": "House",
    "cat": "symbols"
  },
  {
    "code": "house_with_garden",
    "char": "🏡",
    "name": "House with garden",
    "cat": "symbols"
  },
  {
    "code": "houses",
    "char": "🏘",
    "name": "Houses",
    "cat": "symbols"
  },
  {
    "code": "hugs",
    "char": "🤗",
    "name": "Smiling face with open hands",
    "cat": "people"
  },
  {
    "code": "hungary",
    "char": "🇭🇺",
    "name": "Flag: Hungary",
    "cat": "symbols"
  },
  {
    "code": "hushed",
    "char": "😯",
    "name": "Hushed face",
    "cat": "people"
  },
  {
    "code": "hut",
    "char": "🛖",
    "name": "Hut",
    "cat": "symbols"
  },
  {
    "code": "hyacinth",
    "char": "🪻",
    "name": "Hyacinth",
    "cat": "symbols"
  },
  {
    "code": "ice_cream",
    "char": "🍨",
    "name": "Ice cream",
    "cat": "symbols"
  },
  {
    "code": "ice_cube",
    "char": "🧊",
    "name": "Ice",
    "cat": "symbols"
  },
  {
    "code": "ice_hockey",
    "char": "🏒",
    "name": "Ice hockey",
    "cat": "symbols"
  },
  {
    "code": "ice_skate",
    "char": "⛸",
    "name": "Ice skate",
    "cat": "symbols"
  },
  {
    "code": "icecream",
    "char": "🍦",
    "name": "Soft ice cream",
    "cat": "symbols"
  },
  {
    "code": "iceland",
    "char": "🇮🇸",
    "name": "Flag: Iceland",
    "cat": "symbols"
  },
  {
    "code": "id",
    "char": "🆔",
    "name": "ID button",
    "cat": "symbols"
  },
  {
    "code": "identification_card",
    "char": "🪪",
    "name": "Identification card",
    "cat": "tech"
  },
  {
    "code": "ideograph_advantage",
    "char": "🉐",
    "name": "Japanese “bargain” button",
    "cat": "symbols"
  },
  {
    "code": "imp",
    "char": "👿",
    "name": "Angry face with horns",
    "cat": "people"
  },
  {
    "code": "inbox_tray",
    "char": "📥",
    "name": "Inbox tray",
    "cat": "tech"
  },
  {
    "code": "incoming_envelope",
    "char": "📨",
    "name": "Incoming envelope",
    "cat": "tech"
  },
  {
    "code": "index_pointing_at_the_viewer",
    "char": "🫵",
    "name": "Index pointing at the viewer",
    "cat": "people"
  },
  {
    "code": "india",
    "char": "🇮🇳",
    "name": "Flag: India",
    "cat": "symbols"
  },
  {
    "code": "indonesia",
    "char": "🇮🇩",
    "name": "Flag: Indonesia",
    "cat": "symbols"
  },
  {
    "code": "infinity",
    "char": "♾",
    "name": "Infinity",
    "cat": "symbols"
  },
  {
    "code": "information_desk_person",
    "char": "💁",
    "name": "Person tipping hand",
    "cat": "people"
  },
  {
    "code": "information_source",
    "char": "ℹ",
    "name": "Information",
    "cat": "symbols"
  },
  {
    "code": "innocent",
    "char": "😇",
    "name": "Smiling face with halo",
    "cat": "people"
  },
  {
    "code": "interrobang",
    "char": "⁉",
    "name": "Exclamation question mark",
    "cat": "symbols"
  },
  {
    "code": "iphone",
    "char": "📱",
    "name": "Mobile phone",
    "cat": "tech"
  },
  {
    "code": "iran",
    "char": "🇮🇷",
    "name": "Flag: Iran",
    "cat": "symbols"
  },
  {
    "code": "iraq",
    "char": "🇮🇶",
    "name": "Flag: Iraq",
    "cat": "symbols"
  },
  {
    "code": "ireland",
    "char": "🇮🇪",
    "name": "Flag: Ireland",
    "cat": "symbols"
  },
  {
    "code": "isle_of_man",
    "char": "🇮🇲",
    "name": "Flag: Isle of Man",
    "cat": "symbols"
  },
  {
    "code": "israel",
    "char": "🇮🇱",
    "name": "Flag: Israel",
    "cat": "symbols"
  },
  {
    "code": "it",
    "char": "🇮🇹",
    "name": "Flag: Italy",
    "cat": "symbols"
  },
  {
    "code": "izakaya_lantern",
    "char": "🏮",
    "name": "Red paper lantern",
    "cat": "tech"
  },
  {
    "code": "jack_o_lantern",
    "char": "🎃",
    "name": "Jack-o-lantern",
    "cat": "symbols"
  },
  {
    "code": "jamaica",
    "char": "🇯🇲",
    "name": "Flag: Jamaica",
    "cat": "symbols"
  },
  {
    "code": "japan",
    "char": "🗾",
    "name": "Map of Japan",
    "cat": "symbols"
  },
  {
    "code": "japanese_castle",
    "char": "🏯",
    "name": "Japanese castle",
    "cat": "symbols"
  },
  {
    "code": "japanese_goblin",
    "char": "👺",
    "name": "Goblin",
    "cat": "people"
  },
  {
    "code": "japanese_ogre",
    "char": "👹",
    "name": "Ogre",
    "cat": "people"
  },
  {
    "code": "jar",
    "char": "🫙",
    "name": "Jar",
    "cat": "symbols"
  },
  {
    "code": "jeans",
    "char": "👖",
    "name": "Jeans",
    "cat": "tech"
  },
  {
    "code": "jellyfish",
    "char": "🪼",
    "name": "Jellyfish",
    "cat": "symbols"
  },
  {
    "code": "jersey",
    "char": "🇯🇪",
    "name": "Flag: Jersey",
    "cat": "symbols"
  },
  {
    "code": "jigsaw",
    "char": "🧩",
    "name": "Puzzle piece",
    "cat": "symbols"
  },
  {
    "code": "jordan",
    "char": "🇯🇴",
    "name": "Flag: Jordan",
    "cat": "symbols"
  },
  {
    "code": "joy_cat",
    "char": "😹",
    "name": "Cat with tears of joy",
    "cat": "people"
  },
  {
    "code": "joystick",
    "char": "🕹",
    "name": "Joystick",
    "cat": "tech"
  },
  {
    "code": "jp",
    "char": "🇯🇵",
    "name": "Flag: Japan",
    "cat": "symbols"
  },
  {
    "code": "judge",
    "char": "🧑⚖",
    "name": "Judge",
    "cat": "people"
  },
  {
    "code": "juggling_person",
    "char": "🤹",
    "name": "Person juggling",
    "cat": "people"
  },
  {
    "code": "kaaba",
    "char": "🕋",
    "name": "Kaaba",
    "cat": "symbols"
  },
  {
    "code": "kangaroo",
    "char": "🦘",
    "name": "Kangaroo",
    "cat": "symbols"
  },
  {
    "code": "kazakhstan",
    "char": "🇰🇿",
    "name": "Flag: Kazakhstan",
    "cat": "symbols"
  },
  {
    "code": "kenya",
    "char": "🇰🇪",
    "name": "Flag: Kenya",
    "cat": "symbols"
  },
  {
    "code": "keyboard",
    "char": "⌨",
    "name": "Keyboard",
    "cat": "tech"
  },
  {
    "code": "keycap_ten",
    "char": "🔟",
    "name": "Keycap: 10",
    "cat": "symbols"
  },
  {
    "code": "khanda",
    "char": "🪯",
    "name": "Khanda",
    "cat": "symbols"
  },
  {
    "code": "kick_scooter",
    "char": "🛴",
    "name": "Kick scooter",
    "cat": "symbols"
  },
  {
    "code": "kimono",
    "char": "👘",
    "name": "Kimono",
    "cat": "tech"
  },
  {
    "code": "kiribati",
    "char": "🇰🇮",
    "name": "Flag: Kiribati",
    "cat": "symbols"
  },
  {
    "code": "kiss",
    "char": "💋",
    "name": "Kiss mark",
    "cat": "people"
  },
  {
    "code": "kissing",
    "char": "😗",
    "name": "Kissing face",
    "cat": "people"
  },
  {
    "code": "kissing_cat",
    "char": "😽",
    "name": "Kissing cat",
    "cat": "people"
  },
  {
    "code": "kissing_closed_eyes",
    "char": "😚",
    "name": "Kissing face with closed eyes",
    "cat": "people"
  },
  {
    "code": "kissing_heart",
    "char": "😘",
    "name": "Face blowing a kiss",
    "cat": "people"
  },
  {
    "code": "kissing_smiling_eyes",
    "char": "😙",
    "name": "Kissing face with smiling eyes",
    "cat": "people"
  },
  {
    "code": "kite",
    "char": "🪁",
    "name": "Kite",
    "cat": "symbols"
  },
  {
    "code": "kiwi_fruit",
    "char": "🥝",
    "name": "Kiwi fruit",
    "cat": "symbols"
  },
  {
    "code": "kneeling_man",
    "char": "🧎♂",
    "name": "Man kneeling",
    "cat": "people"
  },
  {
    "code": "kneeling_person",
    "char": "🧎",
    "name": "Person kneeling",
    "cat": "people"
  },
  {
    "code": "kneeling_woman",
    "char": "🧎♀",
    "name": "Woman kneeling",
    "cat": "people"
  },
  {
    "code": "knife",
    "char": "🔪",
    "name": "Kitchen knife",
    "cat": "symbols"
  },
  {
    "code": "knot",
    "char": "🪢",
    "name": "Knot",
    "cat": "symbols"
  },
  {
    "code": "koala",
    "char": "🐨",
    "name": "Koala",
    "cat": "symbols"
  },
  {
    "code": "koko",
    "char": "🈁",
    "name": "Japanese “here” button",
    "cat": "symbols"
  },
  {
    "code": "kosovo",
    "char": "🇽🇰",
    "name": "Flag: Kosovo",
    "cat": "symbols"
  },
  {
    "code": "kr",
    "char": "🇰🇷",
    "name": "Flag: South Korea",
    "cat": "symbols"
  },
  {
    "code": "kuwait",
    "char": "🇰🇼",
    "name": "Flag: Kuwait",
    "cat": "symbols"
  },
  {
    "code": "kyrgyzstan",
    "char": "🇰🇬",
    "name": "Flag: Kyrgyzstan",
    "cat": "symbols"
  },
  {
    "code": "lab_coat",
    "char": "🥼",
    "name": "Lab coat",
    "cat": "tech"
  },
  {
    "code": "label",
    "char": "🏷",
    "name": "Label",
    "cat": "tech"
  },
  {
    "code": "lacrosse",
    "char": "🥍",
    "name": "Lacrosse",
    "cat": "symbols"
  },
  {
    "code": "ladder",
    "char": "🪜",
    "name": "Ladder",
    "cat": "tech"
  },
  {
    "code": "lady_beetle",
    "char": "🐞",
    "name": "Lady beetle",
    "cat": "symbols"
  },
  {
    "code": "lantern",
    "char": "🏮",
    "name": "Red paper lantern",
    "cat": "tech"
  },
  {
    "code": "laos",
    "char": "🇱🇦",
    "name": "Flag: Laos",
    "cat": "symbols"
  },
  {
    "code": "large_blue_circle",
    "char": "🔵",
    "name": "Blue circle",
    "cat": "symbols"
  },
  {
    "code": "large_blue_diamond",
    "char": "🔷",
    "name": "Large blue diamond",
    "cat": "symbols"
  },
  {
    "code": "large_orange_diamond",
    "char": "🔶",
    "name": "Large orange diamond",
    "cat": "symbols"
  },
  {
    "code": "last_quarter_moon",
    "char": "🌗",
    "name": "Last quarter moon",
    "cat": "symbols"
  },
  {
    "code": "last_quarter_moon_with_face",
    "char": "🌜",
    "name": "Last quarter moon face",
    "cat": "symbols"
  },
  {
    "code": "latin_cross",
    "char": "✝",
    "name": "Latin cross",
    "cat": "symbols"
  },
  {
    "code": "latvia",
    "char": "🇱🇻",
    "name": "Flag: Latvia",
    "cat": "symbols"
  },
  {
    "code": "laughing",
    "char": "😆",
    "name": "Grinning squinting face",
    "cat": "people"
  },
  {
    "code": "leafy_green",
    "char": "🥬",
    "name": "Leafy green",
    "cat": "symbols"
  },
  {
    "code": "leaves",
    "char": "🍃",
    "name": "Leaf fluttering in wind",
    "cat": "symbols"
  },
  {
    "code": "lebanon",
    "char": "🇱🇧",
    "name": "Flag: Lebanon",
    "cat": "symbols"
  },
  {
    "code": "ledger",
    "char": "📒",
    "name": "Ledger",
    "cat": "tech"
  },
  {
    "code": "left_luggage",
    "char": "🛅",
    "name": "Left luggage",
    "cat": "symbols"
  },
  {
    "code": "left_right_arrow",
    "char": "↔",
    "name": "Left-right arrow",
    "cat": "symbols"
  },
  {
    "code": "left_speech_bubble",
    "char": "🗨",
    "name": "Left speech bubble",
    "cat": "people"
  },
  {
    "code": "leftwards_arrow_with_hook",
    "char": "↩",
    "name": "Right arrow curving left",
    "cat": "symbols"
  },
  {
    "code": "leftwards_hand",
    "char": "🫲",
    "name": "Leftwards hand",
    "cat": "people"
  },
  {
    "code": "leftwards_pushing_hand",
    "char": "🫷",
    "name": "Leftwards pushing hand",
    "cat": "people"
  },
  {
    "code": "leg",
    "char": "🦵",
    "name": "Leg",
    "cat": "people"
  },
  {
    "code": "lemon",
    "char": "🍋",
    "name": "Lemon",
    "cat": "symbols"
  },
  {
    "code": "leo",
    "char": "♌",
    "name": "Leo",
    "cat": "symbols"
  },
  {
    "code": "leopard",
    "char": "🐆",
    "name": "Leopard",
    "cat": "symbols"
  },
  {
    "code": "lesotho",
    "char": "🇱🇸",
    "name": "Flag: Lesotho",
    "cat": "symbols"
  },
  {
    "code": "level_slider",
    "char": "🎚",
    "name": "Level slider",
    "cat": "tech"
  },
  {
    "code": "liberia",
    "char": "🇱🇷",
    "name": "Flag: Liberia",
    "cat": "symbols"
  },
  {
    "code": "libra",
    "char": "♎",
    "name": "Libra",
    "cat": "symbols"
  },
  {
    "code": "libya",
    "char": "🇱🇾",
    "name": "Flag: Libya",
    "cat": "symbols"
  },
  {
    "code": "liechtenstein",
    "char": "🇱🇮",
    "name": "Flag: Liechtenstein",
    "cat": "symbols"
  },
  {
    "code": "light_blue_heart",
    "char": "🩵",
    "name": "Light blue heart",
    "cat": "people"
  },
  {
    "code": "light_rail",
    "char": "🚈",
    "name": "Light rail",
    "cat": "symbols"
  },
  {
    "code": "link",
    "char": "🔗",
    "name": "Link",
    "cat": "tech"
  },
  {
    "code": "lion",
    "char": "🦁",
    "name": "Lion",
    "cat": "symbols"
  },
  {
    "code": "lips",
    "char": "👄",
    "name": "Mouth",
    "cat": "people"
  },
  {
    "code": "lipstick",
    "char": "💄",
    "name": "Lipstick",
    "cat": "tech"
  },
  {
    "code": "lithuania",
    "char": "🇱🇹",
    "name": "Flag: Lithuania",
    "cat": "symbols"
  },
  {
    "code": "lizard",
    "char": "🦎",
    "name": "Lizard",
    "cat": "symbols"
  },
  {
    "code": "llama",
    "char": "🦙",
    "name": "Llama",
    "cat": "symbols"
  },
  {
    "code": "lobster",
    "char": "🦞",
    "name": "Lobster",
    "cat": "symbols"
  },
  {
    "code": "lock_with_ink_pen",
    "char": "🔏",
    "name": "Locked with pen",
    "cat": "tech"
  },
  {
    "code": "lollipop",
    "char": "🍭",
    "name": "Lollipop",
    "cat": "symbols"
  },
  {
    "code": "long_drum",
    "char": "🪘",
    "name": "Long drum",
    "cat": "tech"
  },
  {
    "code": "loop",
    "char": "➿",
    "name": "Double curly loop",
    "cat": "symbols"
  },
  {
    "code": "lotion_bottle",
    "char": "🧴",
    "name": "Lotion bottle",
    "cat": "tech"
  },
  {
    "code": "lotus",
    "char": "🪷",
    "name": "Lotus",
    "cat": "symbols"
  },
  {
    "code": "lotus_position",
    "char": "🧘",
    "name": "Person in lotus position",
    "cat": "people"
  },
  {
    "code": "lotus_position_man",
    "char": "🧘♂",
    "name": "Man in lotus position",
    "cat": "people"
  },
  {
    "code": "lotus_position_woman",
    "char": "🧘♀",
    "name": "Woman in lotus position",
    "cat": "people"
  },
  {
    "code": "loud_sound",
    "char": "🔊",
    "name": "Speaker high volume",
    "cat": "tech"
  },
  {
    "code": "loudspeaker",
    "char": "📢",
    "name": "Loudspeaker",
    "cat": "status"
  },
  {
    "code": "love_hotel",
    "char": "🏩",
    "name": "Love hotel",
    "cat": "symbols"
  },
  {
    "code": "love_letter",
    "char": "💌",
    "name": "Love letter",
    "cat": "people"
  },
  {
    "code": "love_you_gesture",
    "char": "🤟",
    "name": "Love-you gesture",
    "cat": "people"
  },
  {
    "code": "low_battery",
    "char": "🪫",
    "name": "Low battery",
    "cat": "tech"
  },
  {
    "code": "low_brightness",
    "char": "🔅",
    "name": "Dim button",
    "cat": "symbols"
  },
  {
    "code": "luggage",
    "char": "🧳",
    "name": "Luggage",
    "cat": "symbols"
  },
  {
    "code": "lungs",
    "char": "🫁",
    "name": "Lungs",
    "cat": "people"
  },
  {
    "code": "luxembourg",
    "char": "🇱🇺",
    "name": "Flag: Luxembourg",
    "cat": "symbols"
  },
  {
    "code": "lying_face",
    "char": "🤥",
    "name": "Lying face",
    "cat": "people"
  },
  {
    "code": "m",
    "char": "Ⓜ",
    "name": "Circled M",
    "cat": "symbols"
  },
  {
    "code": "macau",
    "char": "🇲🇴",
    "name": "Flag: Macao SAR China",
    "cat": "symbols"
  },
  {
    "code": "macedonia",
    "char": "🇲🇰",
    "name": "Flag: North Macedonia",
    "cat": "symbols"
  },
  {
    "code": "madagascar",
    "char": "🇲🇬",
    "name": "Flag: Madagascar",
    "cat": "symbols"
  },
  {
    "code": "mag",
    "char": "🔍",
    "name": "Magnifying glass tilted left",
    "cat": "tech"
  },
  {
    "code": "mag_right",
    "char": "🔎",
    "name": "Magnifying glass tilted right",
    "cat": "tech"
  },
  {
    "code": "mage",
    "char": "🧙",
    "name": "Mage",
    "cat": "people"
  },
  {
    "code": "mage_man",
    "char": "🧙♂",
    "name": "Man mage",
    "cat": "people"
  },
  {
    "code": "mage_woman",
    "char": "🧙♀",
    "name": "Woman mage",
    "cat": "people"
  },
  {
    "code": "magic_wand",
    "char": "🪄",
    "name": "Magic wand",
    "cat": "symbols"
  },
  {
    "code": "magnet",
    "char": "🧲",
    "name": "Magnet",
    "cat": "tech"
  },
  {
    "code": "mahjong",
    "char": "🀄",
    "name": "Mahjong red dragon",
    "cat": "symbols"
  },
  {
    "code": "mailbox",
    "char": "📫",
    "name": "Closed mailbox with raised flag",
    "cat": "tech"
  },
  {
    "code": "mailbox_closed",
    "char": "📪",
    "name": "Closed mailbox with lowered flag",
    "cat": "tech"
  },
  {
    "code": "mailbox_with_mail",
    "char": "📬",
    "name": "Open mailbox with raised flag",
    "cat": "tech"
  },
  {
    "code": "mailbox_with_no_mail",
    "char": "📭",
    "name": "Open mailbox with lowered flag",
    "cat": "tech"
  },
  {
    "code": "malawi",
    "char": "🇲🇼",
    "name": "Flag: Malawi",
    "cat": "symbols"
  },
  {
    "code": "malaysia",
    "char": "🇲🇾",
    "name": "Flag: Malaysia",
    "cat": "symbols"
  },
  {
    "code": "maldives",
    "char": "🇲🇻",
    "name": "Flag: Maldives",
    "cat": "symbols"
  },
  {
    "code": "male_detective",
    "char": "🕵♂",
    "name": "Man detective",
    "cat": "people"
  },
  {
    "code": "male_sign",
    "char": "♂",
    "name": "Male sign",
    "cat": "symbols"
  },
  {
    "code": "mali",
    "char": "🇲🇱",
    "name": "Flag: Mali",
    "cat": "symbols"
  },
  {
    "code": "malta",
    "char": "🇲🇹",
    "name": "Flag: Malta",
    "cat": "symbols"
  },
  {
    "code": "mammoth",
    "char": "🦣",
    "name": "Mammoth",
    "cat": "symbols"
  },
  {
    "code": "man",
    "char": "👨",
    "name": "Man",
    "cat": "people"
  },
  {
    "code": "man_artist",
    "char": "👨🎨",
    "name": "Man artist",
    "cat": "people"
  },
  {
    "code": "man_astronaut",
    "char": "👨🚀",
    "name": "Man astronaut",
    "cat": "people"
  },
  {
    "code": "man_beard",
    "char": "🧔♂",
    "name": "Man: beard",
    "cat": "people"
  },
  {
    "code": "man_cartwheeling",
    "char": "🤸♂",
    "name": "Man cartwheeling",
    "cat": "people"
  },
  {
    "code": "man_cook",
    "char": "👨🍳",
    "name": "Man cook",
    "cat": "people"
  },
  {
    "code": "man_dancing",
    "char": "🕺",
    "name": "Man dancing",
    "cat": "people"
  },
  {
    "code": "man_facepalming",
    "char": "🤦♂",
    "name": "Man facepalming",
    "cat": "people"
  },
  {
    "code": "man_factory_worker",
    "char": "👨🏭",
    "name": "Man factory worker",
    "cat": "people"
  },
  {
    "code": "man_farmer",
    "char": "👨🌾",
    "name": "Man farmer",
    "cat": "people"
  },
  {
    "code": "man_feeding_baby",
    "char": "👨🍼",
    "name": "Man feeding baby",
    "cat": "people"
  },
  {
    "code": "man_firefighter",
    "char": "👨🚒",
    "name": "Man firefighter",
    "cat": "people"
  },
  {
    "code": "man_health_worker",
    "char": "👨⚕",
    "name": "Man health worker",
    "cat": "people"
  },
  {
    "code": "man_in_manual_wheelchair",
    "char": "👨🦽",
    "name": "Man in manual wheelchair",
    "cat": "people"
  },
  {
    "code": "man_in_motorized_wheelchair",
    "char": "👨🦼",
    "name": "Man in motorized wheelchair",
    "cat": "people"
  },
  {
    "code": "man_in_tuxedo",
    "char": "🤵♂",
    "name": "Man in tuxedo",
    "cat": "people"
  },
  {
    "code": "man_judge",
    "char": "👨⚖",
    "name": "Man judge",
    "cat": "people"
  },
  {
    "code": "man_juggling",
    "char": "🤹♂",
    "name": "Man juggling",
    "cat": "people"
  },
  {
    "code": "man_mechanic",
    "char": "👨🔧",
    "name": "Man mechanic",
    "cat": "people"
  },
  {
    "code": "man_office_worker",
    "char": "👨💼",
    "name": "Man office worker",
    "cat": "people"
  },
  {
    "code": "man_pilot",
    "char": "👨✈",
    "name": "Man pilot",
    "cat": "people"
  },
  {
    "code": "man_playing_handball",
    "char": "🤾♂",
    "name": "Man playing handball",
    "cat": "people"
  },
  {
    "code": "man_playing_water_polo",
    "char": "🤽♂",
    "name": "Man playing water polo",
    "cat": "people"
  },
  {
    "code": "man_scientist",
    "char": "👨🔬",
    "name": "Man scientist",
    "cat": "people"
  },
  {
    "code": "man_shrugging",
    "char": "🤷♂",
    "name": "Man shrugging",
    "cat": "people"
  },
  {
    "code": "man_singer",
    "char": "👨🎤",
    "name": "Man singer",
    "cat": "people"
  },
  {
    "code": "man_student",
    "char": "👨🎓",
    "name": "Man student",
    "cat": "people"
  },
  {
    "code": "man_teacher",
    "char": "👨🏫",
    "name": "Man teacher",
    "cat": "people"
  },
  {
    "code": "man_technologist",
    "char": "👨💻",
    "name": "Man technologist",
    "cat": "people"
  },
  {
    "code": "man_with_gua_pi_mao",
    "char": "👲",
    "name": "Person with skullcap",
    "cat": "people"
  },
  {
    "code": "man_with_probing_cane",
    "char": "👨🦯",
    "name": "Man with white cane",
    "cat": "people"
  },
  {
    "code": "man_with_turban",
    "char": "👳♂",
    "name": "Man wearing turban",
    "cat": "people"
  },
  {
    "code": "man_with_veil",
    "char": "👰♂",
    "name": "Man with veil",
    "cat": "people"
  },
  {
    "code": "mandarin",
    "char": "🍊",
    "name": "Tangerine",
    "cat": "symbols"
  },
  {
    "code": "mango",
    "char": "🥭",
    "name": "Mango",
    "cat": "symbols"
  },
  {
    "code": "mans_shoe",
    "char": "👞",
    "name": "Man’s shoe",
    "cat": "tech"
  },
  {
    "code": "mantelpiece_clock",
    "char": "🕰",
    "name": "Mantelpiece clock",
    "cat": "symbols"
  },
  {
    "code": "manual_wheelchair",
    "char": "🦽",
    "name": "Manual wheelchair",
    "cat": "symbols"
  },
  {
    "code": "maple_leaf",
    "char": "🍁",
    "name": "Maple leaf",
    "cat": "symbols"
  },
  {
    "code": "maracas",
    "char": "🪇",
    "name": "Maracas",
    "cat": "tech"
  },
  {
    "code": "marshall_islands",
    "char": "🇲🇭",
    "name": "Flag: Marshall Islands",
    "cat": "symbols"
  },
  {
    "code": "martial_arts_uniform",
    "char": "🥋",
    "name": "Martial arts uniform",
    "cat": "symbols"
  },
  {
    "code": "martinique",
    "char": "🇲🇶",
    "name": "Flag: Martinique",
    "cat": "symbols"
  },
  {
    "code": "mask",
    "char": "😷",
    "name": "Face with medical mask",
    "cat": "people"
  },
  {
    "code": "massage",
    "char": "💆",
    "name": "Person getting massage",
    "cat": "people"
  },
  {
    "code": "massage_man",
    "char": "💆♂",
    "name": "Man getting massage",
    "cat": "people"
  },
  {
    "code": "massage_woman",
    "char": "💆♀",
    "name": "Woman getting massage",
    "cat": "people"
  },
  {
    "code": "mate",
    "char": "🧉",
    "name": "Mate",
    "cat": "symbols"
  },
  {
    "code": "mauritania",
    "char": "🇲🇷",
    "name": "Flag: Mauritania",
    "cat": "symbols"
  },
  {
    "code": "mauritius",
    "char": "🇲🇺",
    "name": "Flag: Mauritius",
    "cat": "symbols"
  },
  {
    "code": "mayotte",
    "char": "🇾🇹",
    "name": "Flag: Mayotte",
    "cat": "symbols"
  },
  {
    "code": "meat_on_bone",
    "char": "🍖",
    "name": "Meat on bone",
    "cat": "symbols"
  },
  {
    "code": "mechanic",
    "char": "🧑🔧",
    "name": "Mechanic",
    "cat": "people"
  },
  {
    "code": "mechanical_arm",
    "char": "🦾",
    "name": "Mechanical arm",
    "cat": "people"
  },
  {
    "code": "mechanical_leg",
    "char": "🦿",
    "name": "Mechanical leg",
    "cat": "people"
  },
  {
    "code": "medal_military",
    "char": "🎖",
    "name": "Military medal",
    "cat": "symbols"
  },
  {
    "code": "medal_sports",
    "char": "🏅",
    "name": "Sports medal",
    "cat": "symbols"
  },
  {
    "code": "medical_symbol",
    "char": "⚕",
    "name": "Medical symbol",
    "cat": "symbols"
  },
  {
    "code": "mega",
    "char": "📣",
    "name": "Megaphone",
    "cat": "status"
  },
  {
    "code": "melon",
    "char": "🍈",
    "name": "Melon",
    "cat": "symbols"
  },
  {
    "code": "melting_face",
    "char": "🫠",
    "name": "Melting face",
    "cat": "people"
  },
  {
    "code": "men_wrestling",
    "char": "🤼♂",
    "name": "Men wrestling",
    "cat": "people"
  },
  {
    "code": "mending_heart",
    "char": "❤🩹",
    "name": "Mending heart",
    "cat": "people"
  },
  {
    "code": "menorah",
    "char": "🕎",
    "name": "Menorah",
    "cat": "symbols"
  },
  {
    "code": "mens",
    "char": "🚹",
    "name": "Men’s room",
    "cat": "symbols"
  },
  {
    "code": "mermaid",
    "char": "🧜♀",
    "name": "Mermaid",
    "cat": "people"
  },
  {
    "code": "merman",
    "char": "🧜♂",
    "name": "Merman",
    "cat": "people"
  },
  {
    "code": "merperson",
    "char": "🧜",
    "name": "Merperson",
    "cat": "people"
  },
  {
    "code": "metal",
    "char": "🤘",
    "name": "Sign of the horns",
    "cat": "people"
  },
  {
    "code": "metro",
    "char": "🚇",
    "name": "Metro",
    "cat": "symbols"
  },
  {
    "code": "mexico",
    "char": "🇲🇽",
    "name": "Flag: Mexico",
    "cat": "symbols"
  },
  {
    "code": "microbe",
    "char": "🦠",
    "name": "Microbe",
    "cat": "symbols"
  },
  {
    "code": "micronesia",
    "char": "🇫🇲",
    "name": "Flag: Micronesia",
    "cat": "symbols"
  },
  {
    "code": "microphone",
    "char": "🎤",
    "name": "Microphone",
    "cat": "tech"
  },
  {
    "code": "microscope",
    "char": "🔬",
    "name": "Microscope",
    "cat": "tech"
  },
  {
    "code": "middle_finger",
    "char": "🖕",
    "name": "Middle finger",
    "cat": "people"
  },
  {
    "code": "military_helmet",
    "char": "🪖",
    "name": "Military helmet",
    "cat": "tech"
  },
  {
    "code": "milk_glass",
    "char": "🥛",
    "name": "Glass of milk",
    "cat": "symbols"
  },
  {
    "code": "milky_way",
    "char": "🌌",
    "name": "Milky way",
    "cat": "symbols"
  },
  {
    "code": "minibus",
    "char": "🚐",
    "name": "Minibus",
    "cat": "symbols"
  },
  {
    "code": "minidisc",
    "char": "💽",
    "name": "Computer disk",
    "cat": "tech"
  },
  {
    "code": "mirror",
    "char": "🪞",
    "name": "Mirror",
    "cat": "tech"
  },
  {
    "code": "mirror_ball",
    "char": "🪩",
    "name": "Mirror ball",
    "cat": "symbols"
  },
  {
    "code": "mobile_phone_off",
    "char": "📴",
    "name": "Mobile phone off",
    "cat": "symbols"
  },
  {
    "code": "moldova",
    "char": "🇲🇩",
    "name": "Flag: Moldova",
    "cat": "symbols"
  },
  {
    "code": "monaco",
    "char": "🇲🇨",
    "name": "Flag: Monaco",
    "cat": "symbols"
  },
  {
    "code": "money_mouth_face",
    "char": "🤑",
    "name": "Money-mouth face",
    "cat": "people"
  },
  {
    "code": "money_with_wings",
    "char": "💸",
    "name": "Money with wings",
    "cat": "tech"
  },
  {
    "code": "moneybag",
    "char": "💰",
    "name": "Money bag",
    "cat": "tech"
  },
  {
    "code": "mongolia",
    "char": "🇲🇳",
    "name": "Flag: Mongolia",
    "cat": "symbols"
  },
  {
    "code": "monkey",
    "char": "🐒",
    "name": "Monkey",
    "cat": "symbols"
  },
  {
    "code": "monkey_face",
    "char": "🐵",
    "name": "Monkey face",
    "cat": "symbols"
  },
  {
    "code": "monocle_face",
    "char": "🧐",
    "name": "Face with monocle",
    "cat": "people"
  },
  {
    "code": "monorail",
    "char": "🚝",
    "name": "Monorail",
    "cat": "symbols"
  },
  {
    "code": "montenegro",
    "char": "🇲🇪",
    "name": "Flag: Montenegro",
    "cat": "symbols"
  },
  {
    "code": "montserrat",
    "char": "🇲🇸",
    "name": "Flag: Montserrat",
    "cat": "symbols"
  },
  {
    "code": "moon",
    "char": "🌔",
    "name": "Waxing gibbous moon",
    "cat": "symbols"
  },
  {
    "code": "moon_cake",
    "char": "🥮",
    "name": "Moon cake",
    "cat": "symbols"
  },
  {
    "code": "moose",
    "char": "🫎",
    "name": "Moose",
    "cat": "symbols"
  },
  {
    "code": "morocco",
    "char": "🇲🇦",
    "name": "Flag: Morocco",
    "cat": "symbols"
  },
  {
    "code": "mortar_board",
    "char": "🎓",
    "name": "Graduation cap",
    "cat": "tech"
  },
  {
    "code": "mosque",
    "char": "🕌",
    "name": "Mosque",
    "cat": "symbols"
  },
  {
    "code": "mosquito",
    "char": "🦟",
    "name": "Mosquito",
    "cat": "symbols"
  },
  {
    "code": "motor_boat",
    "char": "🛥",
    "name": "Motor boat",
    "cat": "symbols"
  },
  {
    "code": "motor_scooter",
    "char": "🛵",
    "name": "Motor scooter",
    "cat": "symbols"
  },
  {
    "code": "motorcycle",
    "char": "🏍",
    "name": "Motorcycle",
    "cat": "symbols"
  },
  {
    "code": "motorized_wheelchair",
    "char": "🦼",
    "name": "Motorized wheelchair",
    "cat": "symbols"
  },
  {
    "code": "motorway",
    "char": "🛣",
    "name": "Motorway",
    "cat": "symbols"
  },
  {
    "code": "mount_fuji",
    "char": "🗻",
    "name": "Mount fuji",
    "cat": "symbols"
  },
  {
    "code": "mountain",
    "char": "⛰",
    "name": "Mountain",
    "cat": "symbols"
  },
  {
    "code": "mountain_bicyclist",
    "char": "🚵",
    "name": "Person mountain biking",
    "cat": "people"
  },
  {
    "code": "mountain_biking_man",
    "char": "🚵♂",
    "name": "Man mountain biking",
    "cat": "people"
  },
  {
    "code": "mountain_biking_woman",
    "char": "🚵♀",
    "name": "Woman mountain biking",
    "cat": "people"
  },
  {
    "code": "mountain_cableway",
    "char": "🚠",
    "name": "Mountain cableway",
    "cat": "symbols"
  },
  {
    "code": "mountain_railway",
    "char": "🚞",
    "name": "Mountain railway",
    "cat": "symbols"
  },
  {
    "code": "mountain_snow",
    "char": "🏔",
    "name": "Snow-capped mountain",
    "cat": "symbols"
  },
  {
    "code": "mouse",
    "char": "🐭",
    "name": "Mouse face",
    "cat": "tech"
  },
  {
    "code": "mouse_trap",
    "char": "🪤",
    "name": "Mouse trap",
    "cat": "tech"
  },
  {
    "code": "mouse2",
    "char": "🐁",
    "name": "Mouse",
    "cat": "symbols"
  },
  {
    "code": "movie_camera",
    "char": "🎥",
    "name": "Movie camera",
    "cat": "tech"
  },
  {
    "code": "moyai",
    "char": "🗿",
    "name": "Moai",
    "cat": "tech"
  },
  {
    "code": "mozambique",
    "char": "🇲🇿",
    "name": "Flag: Mozambique",
    "cat": "symbols"
  },
  {
    "code": "mrs_claus",
    "char": "🤶",
    "name": "Mrs. Claus",
    "cat": "people"
  },
  {
    "code": "mushroom",
    "char": "🍄",
    "name": "Mushroom",
    "cat": "symbols"
  },
  {
    "code": "musical_keyboard",
    "char": "🎹",
    "name": "Musical keyboard",
    "cat": "tech"
  },
  {
    "code": "musical_note",
    "char": "🎵",
    "name": "Musical note",
    "cat": "tech"
  },
  {
    "code": "musical_score",
    "char": "🎼",
    "name": "Musical score",
    "cat": "tech"
  },
  {
    "code": "mute",
    "char": "🔇",
    "name": "Muted speaker",
    "cat": "tech"
  },
  {
    "code": "mx_claus",
    "char": "🧑🎄",
    "name": "Mx claus",
    "cat": "people"
  },
  {
    "code": "myanmar",
    "char": "🇲🇲",
    "name": "Flag: Myanmar (Burma)",
    "cat": "symbols"
  },
  {
    "code": "nail_care",
    "char": "💅",
    "name": "Nail polish",
    "cat": "people"
  },
  {
    "code": "name_badge",
    "char": "📛",
    "name": "Name badge",
    "cat": "symbols"
  },
  {
    "code": "namibia",
    "char": "🇳🇦",
    "name": "Flag: Namibia",
    "cat": "symbols"
  },
  {
    "code": "national_park",
    "char": "🏞",
    "name": "National park",
    "cat": "symbols"
  },
  {
    "code": "nauru",
    "char": "🇳🇷",
    "name": "Flag: Nauru",
    "cat": "symbols"
  },
  {
    "code": "nauseated_face",
    "char": "🤢",
    "name": "Nauseated face",
    "cat": "people"
  },
  {
    "code": "nazar_amulet",
    "char": "🧿",
    "name": "Nazar amulet",
    "cat": "tech"
  },
  {
    "code": "necktie",
    "char": "👔",
    "name": "Necktie",
    "cat": "tech"
  },
  {
    "code": "negative_squared_cross_mark",
    "char": "❎",
    "name": "Cross mark button",
    "cat": "symbols"
  },
  {
    "code": "nepal",
    "char": "🇳🇵",
    "name": "Flag: Nepal",
    "cat": "symbols"
  },
  {
    "code": "nest_with_eggs",
    "char": "🪺",
    "name": "Nest with eggs",
    "cat": "symbols"
  },
  {
    "code": "nesting_dolls",
    "char": "🪆",
    "name": "Nesting dolls",
    "cat": "symbols"
  },
  {
    "code": "netherlands",
    "char": "🇳🇱",
    "name": "Flag: Netherlands",
    "cat": "symbols"
  },
  {
    "code": "neutral_face",
    "char": "😐",
    "name": "Neutral face",
    "cat": "people"
  },
  {
    "code": "new",
    "char": "🆕",
    "name": "NEW button",
    "cat": "symbols"
  },
  {
    "code": "new_caledonia",
    "char": "🇳🇨",
    "name": "Flag: New Caledonia",
    "cat": "symbols"
  },
  {
    "code": "new_moon",
    "char": "🌑",
    "name": "New moon",
    "cat": "symbols"
  },
  {
    "code": "new_moon_with_face",
    "char": "🌚",
    "name": "New moon face",
    "cat": "symbols"
  },
  {
    "code": "new_zealand",
    "char": "🇳🇿",
    "name": "Flag: New Zealand",
    "cat": "symbols"
  },
  {
    "code": "newspaper",
    "char": "📰",
    "name": "Newspaper",
    "cat": "tech"
  },
  {
    "code": "newspaper_roll",
    "char": "🗞",
    "name": "Rolled-up newspaper",
    "cat": "tech"
  },
  {
    "code": "next_track_button",
    "char": "⏭",
    "name": "Next track button",
    "cat": "symbols"
  },
  {
    "code": "ng",
    "char": "🆖",
    "name": "NG button",
    "cat": "symbols"
  },
  {
    "code": "ng_man",
    "char": "🙅♂",
    "name": "Man gesturing NO",
    "cat": "people"
  },
  {
    "code": "ng_woman",
    "char": "🙅♀",
    "name": "Woman gesturing NO",
    "cat": "people"
  },
  {
    "code": "nicaragua",
    "char": "🇳🇮",
    "name": "Flag: Nicaragua",
    "cat": "symbols"
  },
  {
    "code": "niger",
    "char": "🇳🇪",
    "name": "Flag: Niger",
    "cat": "symbols"
  },
  {
    "code": "nigeria",
    "char": "🇳🇬",
    "name": "Flag: Nigeria",
    "cat": "symbols"
  },
  {
    "code": "night_with_stars",
    "char": "🌃",
    "name": "Night with stars",
    "cat": "symbols"
  },
  {
    "code": "nine",
    "char": "9⃣",
    "name": "Keycap: 9",
    "cat": "symbols"
  },
  {
    "code": "ninja",
    "char": "🥷",
    "name": "Ninja",
    "cat": "people"
  },
  {
    "code": "niue",
    "char": "🇳🇺",
    "name": "Flag: Niue",
    "cat": "symbols"
  },
  {
    "code": "no_bell",
    "char": "🔕",
    "name": "Bell with slash",
    "cat": "status"
  },
  {
    "code": "no_bicycles",
    "char": "🚳",
    "name": "No bicycles",
    "cat": "symbols"
  },
  {
    "code": "no_entry",
    "char": "⛔",
    "name": "No entry",
    "cat": "status"
  },
  {
    "code": "no_entry_sign",
    "char": "🚫",
    "name": "Prohibited",
    "cat": "status"
  },
  {
    "code": "no_good",
    "char": "🙅",
    "name": "Person gesturing NO",
    "cat": "people"
  },
  {
    "code": "no_good_man",
    "char": "🙅♂",
    "name": "Man gesturing NO",
    "cat": "people"
  },
  {
    "code": "no_good_woman",
    "char": "🙅♀",
    "name": "Woman gesturing NO",
    "cat": "people"
  },
  {
    "code": "no_mobile_phones",
    "char": "📵",
    "name": "No mobile phones",
    "cat": "symbols"
  },
  {
    "code": "no_mouth",
    "char": "😶",
    "name": "Face without mouth",
    "cat": "people"
  },
  {
    "code": "no_pedestrians",
    "char": "🚷",
    "name": "No pedestrians",
    "cat": "symbols"
  },
  {
    "code": "no_smoking",
    "char": "🚭",
    "name": "No smoking",
    "cat": "symbols"
  },
  {
    "code": "non-potable_water",
    "char": "🚱",
    "name": "Non-potable water",
    "cat": "symbols"
  },
  {
    "code": "norfolk_island",
    "char": "🇳🇫",
    "name": "Flag: Norfolk Island",
    "cat": "symbols"
  },
  {
    "code": "north_korea",
    "char": "🇰🇵",
    "name": "Flag: North Korea",
    "cat": "symbols"
  },
  {
    "code": "northern_mariana_islands",
    "char": "🇲🇵",
    "name": "Flag: Northern Mariana Islands",
    "cat": "symbols"
  },
  {
    "code": "norway",
    "char": "🇳🇴",
    "name": "Flag: Norway",
    "cat": "symbols"
  },
  {
    "code": "nose",
    "char": "👃",
    "name": "Nose",
    "cat": "people"
  },
  {
    "code": "notebook",
    "char": "📓",
    "name": "Notebook",
    "cat": "tech"
  },
  {
    "code": "notebook_with_decorative_cover",
    "char": "📔",
    "name": "Notebook with decorative cover",
    "cat": "tech"
  },
  {
    "code": "notes",
    "char": "🎶",
    "name": "Musical notes",
    "cat": "tech"
  },
  {
    "code": "nut_and_bolt",
    "char": "🔩",
    "name": "Nut and bolt",
    "cat": "tech"
  },
  {
    "code": "o",
    "char": "⭕",
    "name": "Hollow red circle",
    "cat": "symbols"
  },
  {
    "code": "o2",
    "char": "🅾",
    "name": "O button (blood type)",
    "cat": "symbols"
  },
  {
    "code": "ocean",
    "char": "🌊",
    "name": "Water wave",
    "cat": "symbols"
  },
  {
    "code": "octopus",
    "char": "🐙",
    "name": "Octopus",
    "cat": "symbols"
  },
  {
    "code": "oden",
    "char": "🍢",
    "name": "Oden",
    "cat": "symbols"
  },
  {
    "code": "office",
    "char": "🏢",
    "name": "Office building",
    "cat": "symbols"
  },
  {
    "code": "office_worker",
    "char": "🧑💼",
    "name": "Office worker",
    "cat": "people"
  },
  {
    "code": "oil_drum",
    "char": "🛢",
    "name": "Oil drum",
    "cat": "symbols"
  },
  {
    "code": "ok",
    "char": "🆗",
    "name": "OK button",
    "cat": "symbols"
  },
  {
    "code": "ok_hand",
    "char": "👌",
    "name": "OK hand",
    "cat": "people"
  },
  {
    "code": "ok_man",
    "char": "🙆♂",
    "name": "Man gesturing OK",
    "cat": "people"
  },
  {
    "code": "ok_person",
    "char": "🙆",
    "name": "Person gesturing OK",
    "cat": "people"
  },
  {
    "code": "ok_woman",
    "char": "🙆♀",
    "name": "Woman gesturing OK",
    "cat": "people"
  },
  {
    "code": "old_key",
    "char": "🗝",
    "name": "Old key",
    "cat": "tech"
  },
  {
    "code": "older_adult",
    "char": "🧓",
    "name": "Older person",
    "cat": "people"
  },
  {
    "code": "older_man",
    "char": "👴",
    "name": "Old man",
    "cat": "people"
  },
  {
    "code": "older_woman",
    "char": "👵",
    "name": "Old woman",
    "cat": "people"
  },
  {
    "code": "olive",
    "char": "🫒",
    "name": "Olive",
    "cat": "symbols"
  },
  {
    "code": "om",
    "char": "🕉",
    "name": "Om",
    "cat": "symbols"
  },
  {
    "code": "oman",
    "char": "🇴🇲",
    "name": "Flag: Oman",
    "cat": "symbols"
  },
  {
    "code": "on",
    "char": "🔛",
    "name": "ON! arrow",
    "cat": "symbols"
  },
  {
    "code": "oncoming_automobile",
    "char": "🚘",
    "name": "Oncoming automobile",
    "cat": "symbols"
  },
  {
    "code": "oncoming_bus",
    "char": "🚍",
    "name": "Oncoming bus",
    "cat": "symbols"
  },
  {
    "code": "oncoming_police_car",
    "char": "🚔",
    "name": "Oncoming police car",
    "cat": "symbols"
  },
  {
    "code": "oncoming_taxi",
    "char": "🚖",
    "name": "Oncoming taxi",
    "cat": "symbols"
  },
  {
    "code": "one",
    "char": "1⃣",
    "name": "Keycap: 1",
    "cat": "symbols"
  },
  {
    "code": "one_piece_swimsuit",
    "char": "🩱",
    "name": "One-piece swimsuit",
    "cat": "tech"
  },
  {
    "code": "onion",
    "char": "🧅",
    "name": "Onion",
    "cat": "symbols"
  },
  {
    "code": "open_book",
    "char": "📖",
    "name": "Open book",
    "cat": "tech"
  },
  {
    "code": "open_file_folder",
    "char": "📂",
    "name": "Open file folder",
    "cat": "tech"
  },
  {
    "code": "open_hands",
    "char": "👐",
    "name": "Open hands",
    "cat": "people"
  },
  {
    "code": "open_mouth",
    "char": "😮",
    "name": "Face with open mouth",
    "cat": "people"
  },
  {
    "code": "open_umbrella",
    "char": "☂",
    "name": "Umbrella",
    "cat": "symbols"
  },
  {
    "code": "ophiuchus",
    "char": "⛎",
    "name": "Ophiuchus",
    "cat": "symbols"
  },
  {
    "code": "orange",
    "char": "🍊",
    "name": "Tangerine",
    "cat": "symbols"
  },
  {
    "code": "orange_book",
    "char": "📙",
    "name": "Orange book",
    "cat": "tech"
  },
  {
    "code": "orange_circle",
    "char": "🟠",
    "name": "Orange circle",
    "cat": "status"
  },
  {
    "code": "orange_heart",
    "char": "🧡",
    "name": "Orange heart",
    "cat": "people"
  },
  {
    "code": "orange_square",
    "char": "🟧",
    "name": "Orange square",
    "cat": "symbols"
  },
  {
    "code": "orangutan",
    "char": "🦧",
    "name": "Orangutan",
    "cat": "symbols"
  },
  {
    "code": "orthodox_cross",
    "char": "☦",
    "name": "Orthodox cross",
    "cat": "symbols"
  },
  {
    "code": "otter",
    "char": "🦦",
    "name": "Otter",
    "cat": "symbols"
  },
  {
    "code": "outbox_tray",
    "char": "📤",
    "name": "Outbox tray",
    "cat": "tech"
  },
  {
    "code": "owl",
    "char": "🦉",
    "name": "Owl",
    "cat": "symbols"
  },
  {
    "code": "ox",
    "char": "🐂",
    "name": "Ox",
    "cat": "symbols"
  },
  {
    "code": "oyster",
    "char": "🦪",
    "name": "Oyster",
    "cat": "symbols"
  },
  {
    "code": "page_facing_up",
    "char": "📄",
    "name": "Page facing up",
    "cat": "tech"
  },
  {
    "code": "page_with_curl",
    "char": "📃",
    "name": "Page with curl",
    "cat": "tech"
  },
  {
    "code": "pager",
    "char": "📟",
    "name": "Pager",
    "cat": "tech"
  },
  {
    "code": "paintbrush",
    "char": "🖌",
    "name": "Paintbrush",
    "cat": "tech"
  },
  {
    "code": "pakistan",
    "char": "🇵🇰",
    "name": "Flag: Pakistan",
    "cat": "symbols"
  },
  {
    "code": "palau",
    "char": "🇵🇼",
    "name": "Flag: Palau",
    "cat": "symbols"
  },
  {
    "code": "palestinian_territories",
    "char": "🇵🇸",
    "name": "Flag: Palestinian Territories",
    "cat": "symbols"
  },
  {
    "code": "palm_down_hand",
    "char": "🫳",
    "name": "Palm down hand",
    "cat": "people"
  },
  {
    "code": "palm_tree",
    "char": "🌴",
    "name": "Palm tree",
    "cat": "symbols"
  },
  {
    "code": "palm_up_hand",
    "char": "🫴",
    "name": "Palm up hand",
    "cat": "people"
  },
  {
    "code": "palms_up_together",
    "char": "🤲",
    "name": "Palms up together",
    "cat": "people"
  },
  {
    "code": "panama",
    "char": "🇵🇦",
    "name": "Flag: Panama",
    "cat": "symbols"
  },
  {
    "code": "pancakes",
    "char": "🥞",
    "name": "Pancakes",
    "cat": "symbols"
  },
  {
    "code": "panda_face",
    "char": "🐼",
    "name": "Panda",
    "cat": "symbols"
  },
  {
    "code": "paperclip",
    "char": "📎",
    "name": "Paperclip",
    "cat": "tech"
  },
  {
    "code": "paperclips",
    "char": "🖇",
    "name": "Linked paperclips",
    "cat": "tech"
  },
  {
    "code": "papua_new_guinea",
    "char": "🇵🇬",
    "name": "Flag: Papua New Guinea",
    "cat": "symbols"
  },
  {
    "code": "parachute",
    "char": "🪂",
    "name": "Parachute",
    "cat": "symbols"
  },
  {
    "code": "paraguay",
    "char": "🇵🇾",
    "name": "Flag: Paraguay",
    "cat": "symbols"
  },
  {
    "code": "parasol_on_ground",
    "char": "⛱",
    "name": "Umbrella on ground",
    "cat": "symbols"
  },
  {
    "code": "parking",
    "char": "🅿",
    "name": "P button",
    "cat": "symbols"
  },
  {
    "code": "parrot",
    "char": "🦜",
    "name": "Parrot",
    "cat": "symbols"
  },
  {
    "code": "part_alternation_mark",
    "char": "〽",
    "name": "Part alternation mark",
    "cat": "symbols"
  },
  {
    "code": "partly_sunny",
    "char": "⛅",
    "name": "Sun behind cloud",
    "cat": "symbols"
  },
  {
    "code": "partying_face",
    "char": "🥳",
    "name": "Partying face",
    "cat": "people"
  },
  {
    "code": "passenger_ship",
    "char": "🛳",
    "name": "Passenger ship",
    "cat": "symbols"
  },
  {
    "code": "passport_control",
    "char": "🛂",
    "name": "Passport control",
    "cat": "symbols"
  },
  {
    "code": "pause_button",
    "char": "⏸",
    "name": "Pause button",
    "cat": "symbols"
  },
  {
    "code": "paw_prints",
    "char": "🐾",
    "name": "Paw prints",
    "cat": "symbols"
  },
  {
    "code": "pea_pod",
    "char": "🫛",
    "name": "Pea pod",
    "cat": "symbols"
  },
  {
    "code": "peace_symbol",
    "char": "☮",
    "name": "Peace symbol",
    "cat": "symbols"
  },
  {
    "code": "peach",
    "char": "🍑",
    "name": "Peach",
    "cat": "symbols"
  },
  {
    "code": "peacock",
    "char": "🦚",
    "name": "Peacock",
    "cat": "symbols"
  },
  {
    "code": "peanuts",
    "char": "🥜",
    "name": "Peanuts",
    "cat": "symbols"
  },
  {
    "code": "pear",
    "char": "🍐",
    "name": "Pear",
    "cat": "symbols"
  },
  {
    "code": "pen",
    "char": "🖊",
    "name": "Pen",
    "cat": "tech"
  },
  {
    "code": "pencil",
    "char": "📝",
    "name": "Memo",
    "cat": "tech"
  },
  {
    "code": "pencil2",
    "char": "✏",
    "name": "Pencil",
    "cat": "tech"
  },
  {
    "code": "penguin",
    "char": "🐧",
    "name": "Penguin",
    "cat": "symbols"
  },
  {
    "code": "pensive",
    "char": "😔",
    "name": "Pensive face",
    "cat": "people"
  },
  {
    "code": "people_holding_hands",
    "char": "🧑🤝🧑",
    "name": "People holding hands",
    "cat": "people"
  },
  {
    "code": "people_hugging",
    "char": "🫂",
    "name": "People hugging",
    "cat": "people"
  },
  {
    "code": "performing_arts",
    "char": "🎭",
    "name": "Performing arts",
    "cat": "symbols"
  },
  {
    "code": "persevere",
    "char": "😣",
    "name": "Persevering face",
    "cat": "people"
  },
  {
    "code": "person_bald",
    "char": "🧑🦲",
    "name": "Person: bald",
    "cat": "people"
  },
  {
    "code": "person_curly_hair",
    "char": "🧑🦱",
    "name": "Person: curly hair",
    "cat": "people"
  },
  {
    "code": "person_feeding_baby",
    "char": "🧑🍼",
    "name": "Person feeding baby",
    "cat": "people"
  },
  {
    "code": "person_fencing",
    "char": "🤺",
    "name": "Person fencing",
    "cat": "people"
  },
  {
    "code": "person_in_manual_wheelchair",
    "char": "🧑🦽",
    "name": "Person in manual wheelchair",
    "cat": "people"
  },
  {
    "code": "person_in_motorized_wheelchair",
    "char": "🧑🦼",
    "name": "Person in motorized wheelchair",
    "cat": "people"
  },
  {
    "code": "person_in_tuxedo",
    "char": "🤵",
    "name": "Person in tuxedo",
    "cat": "people"
  },
  {
    "code": "person_red_hair",
    "char": "🧑🦰",
    "name": "Person: red hair",
    "cat": "people"
  },
  {
    "code": "person_white_hair",
    "char": "🧑🦳",
    "name": "Person: white hair",
    "cat": "people"
  },
  {
    "code": "person_with_crown",
    "char": "🫅",
    "name": "Person with crown",
    "cat": "people"
  },
  {
    "code": "person_with_probing_cane",
    "char": "🧑🦯",
    "name": "Person with white cane",
    "cat": "people"
  },
  {
    "code": "person_with_turban",
    "char": "👳",
    "name": "Person wearing turban",
    "cat": "people"
  },
  {
    "code": "person_with_veil",
    "char": "👰",
    "name": "Person with veil",
    "cat": "people"
  },
  {
    "code": "peru",
    "char": "🇵🇪",
    "name": "Flag: Peru",
    "cat": "symbols"
  },
  {
    "code": "petri_dish",
    "char": "🧫",
    "name": "Petri dish",
    "cat": "tech"
  },
  {
    "code": "philippines",
    "char": "🇵🇭",
    "name": "Flag: Philippines",
    "cat": "symbols"
  },
  {
    "code": "phone",
    "char": "☎",
    "name": "Telephone",
    "cat": "tech"
  },
  {
    "code": "pick",
    "char": "⛏",
    "name": "Pick",
    "cat": "tech"
  },
  {
    "code": "pickup_truck",
    "char": "🛻",
    "name": "Pickup truck",
    "cat": "symbols"
  },
  {
    "code": "pie",
    "char": "🥧",
    "name": "Pie",
    "cat": "symbols"
  },
  {
    "code": "pig",
    "char": "🐷",
    "name": "Pig face",
    "cat": "symbols"
  },
  {
    "code": "pig_nose",
    "char": "🐽",
    "name": "Pig nose",
    "cat": "symbols"
  },
  {
    "code": "pig2",
    "char": "🐖",
    "name": "Pig",
    "cat": "symbols"
  },
  {
    "code": "pill",
    "char": "💊",
    "name": "Pill",
    "cat": "tech"
  },
  {
    "code": "pilot",
    "char": "🧑✈",
    "name": "Pilot",
    "cat": "people"
  },
  {
    "code": "pinata",
    "char": "🪅",
    "name": "Piñata",
    "cat": "symbols"
  },
  {
    "code": "pinched_fingers",
    "char": "🤌",
    "name": "Pinched fingers",
    "cat": "people"
  },
  {
    "code": "pinching_hand",
    "char": "🤏",
    "name": "Pinching hand",
    "cat": "people"
  },
  {
    "code": "pineapple",
    "char": "🍍",
    "name": "Pineapple",
    "cat": "symbols"
  },
  {
    "code": "ping_pong",
    "char": "🏓",
    "name": "Ping pong",
    "cat": "symbols"
  },
  {
    "code": "pink_heart",
    "char": "🩷",
    "name": "Pink heart",
    "cat": "people"
  },
  {
    "code": "pirate_flag",
    "char": "🏴☠",
    "name": "Pirate flag",
    "cat": "symbols"
  },
  {
    "code": "pisces",
    "char": "♓",
    "name": "Pisces",
    "cat": "symbols"
  },
  {
    "code": "pitcairn_islands",
    "char": "🇵🇳",
    "name": "Flag: Pitcairn Islands",
    "cat": "symbols"
  },
  {
    "code": "pizza",
    "char": "🍕",
    "name": "Pizza",
    "cat": "symbols"
  },
  {
    "code": "placard",
    "char": "🪧",
    "name": "Placard",
    "cat": "tech"
  },
  {
    "code": "place_of_worship",
    "char": "🛐",
    "name": "Place of worship",
    "cat": "symbols"
  },
  {
    "code": "plate_with_cutlery",
    "char": "🍽",
    "name": "Fork and knife with plate",
    "cat": "symbols"
  },
  {
    "code": "play_or_pause_button",
    "char": "⏯",
    "name": "Play or pause button",
    "cat": "symbols"
  },
  {
    "code": "playground_slide",
    "char": "🛝",
    "name": "Playground slide",
    "cat": "symbols"
  },
  {
    "code": "pleading_face",
    "char": "🥺",
    "name": "Pleading face",
    "cat": "people"
  },
  {
    "code": "plunger",
    "char": "🪠",
    "name": "Plunger",
    "cat": "tech"
  },
  {
    "code": "point_down",
    "char": "👇",
    "name": "Backhand index pointing down",
    "cat": "people"
  },
  {
    "code": "point_left",
    "char": "👈",
    "name": "Backhand index pointing left",
    "cat": "people"
  },
  {
    "code": "point_right",
    "char": "👉",
    "name": "Backhand index pointing right",
    "cat": "people"
  },
  {
    "code": "point_up",
    "char": "☝",
    "name": "Index pointing up",
    "cat": "people"
  },
  {
    "code": "point_up_2",
    "char": "👆",
    "name": "Backhand index pointing up",
    "cat": "people"
  },
  {
    "code": "poland",
    "char": "🇵🇱",
    "name": "Flag: Poland",
    "cat": "symbols"
  },
  {
    "code": "polar_bear",
    "char": "🐻❄",
    "name": "Polar bear",
    "cat": "symbols"
  },
  {
    "code": "police_car",
    "char": "🚓",
    "name": "Police car",
    "cat": "symbols"
  },
  {
    "code": "police_officer",
    "char": "👮",
    "name": "Police officer",
    "cat": "people"
  },
  {
    "code": "policeman",
    "char": "👮♂",
    "name": "Man police officer",
    "cat": "people"
  },
  {
    "code": "policewoman",
    "char": "👮♀",
    "name": "Woman police officer",
    "cat": "people"
  },
  {
    "code": "poodle",
    "char": "🐩",
    "name": "Poodle",
    "cat": "symbols"
  },
  {
    "code": "poop",
    "char": "💩",
    "name": "Pile of poo",
    "cat": "people"
  },
  {
    "code": "popcorn",
    "char": "🍿",
    "name": "Popcorn",
    "cat": "symbols"
  },
  {
    "code": "portugal",
    "char": "🇵🇹",
    "name": "Flag: Portugal",
    "cat": "symbols"
  },
  {
    "code": "post_office",
    "char": "🏣",
    "name": "Japanese post office",
    "cat": "symbols"
  },
  {
    "code": "postal_horn",
    "char": "📯",
    "name": "Postal horn",
    "cat": "tech"
  },
  {
    "code": "postbox",
    "char": "📮",
    "name": "Postbox",
    "cat": "tech"
  },
  {
    "code": "potable_water",
    "char": "🚰",
    "name": "Potable water",
    "cat": "symbols"
  },
  {
    "code": "potato",
    "char": "🥔",
    "name": "Potato",
    "cat": "symbols"
  },
  {
    "code": "potted_plant",
    "char": "🪴",
    "name": "Potted plant",
    "cat": "symbols"
  },
  {
    "code": "pouch",
    "char": "👝",
    "name": "Clutch bag",
    "cat": "tech"
  },
  {
    "code": "poultry_leg",
    "char": "🍗",
    "name": "Poultry leg",
    "cat": "symbols"
  },
  {
    "code": "pound",
    "char": "💷",
    "name": "Pound banknote",
    "cat": "tech"
  },
  {
    "code": "pouring_liquid",
    "char": "🫗",
    "name": "Pouring liquid",
    "cat": "symbols"
  },
  {
    "code": "pout",
    "char": "😡",
    "name": "Enraged face",
    "cat": "people"
  },
  {
    "code": "pouting_cat",
    "char": "😾",
    "name": "Pouting cat",
    "cat": "people"
  },
  {
    "code": "pouting_face",
    "char": "🙎",
    "name": "Person pouting",
    "cat": "people"
  },
  {
    "code": "pouting_man",
    "char": "🙎♂",
    "name": "Man pouting",
    "cat": "people"
  },
  {
    "code": "pouting_woman",
    "char": "🙎♀",
    "name": "Woman pouting",
    "cat": "people"
  },
  {
    "code": "prayer_beads",
    "char": "📿",
    "name": "Prayer beads",
    "cat": "tech"
  },
  {
    "code": "pregnant_man",
    "char": "🫃",
    "name": "Pregnant man",
    "cat": "people"
  },
  {
    "code": "pregnant_person",
    "char": "🫄",
    "name": "Pregnant person",
    "cat": "people"
  },
  {
    "code": "pregnant_woman",
    "char": "🤰",
    "name": "Pregnant woman",
    "cat": "people"
  },
  {
    "code": "pretzel",
    "char": "🥨",
    "name": "Pretzel",
    "cat": "symbols"
  },
  {
    "code": "previous_track_button",
    "char": "⏮",
    "name": "Last track button",
    "cat": "symbols"
  },
  {
    "code": "prince",
    "char": "🤴",
    "name": "Prince",
    "cat": "people"
  },
  {
    "code": "princess",
    "char": "👸",
    "name": "Princess",
    "cat": "people"
  },
  {
    "code": "printer",
    "char": "🖨",
    "name": "Printer",
    "cat": "tech"
  },
  {
    "code": "probing_cane",
    "char": "🦯",
    "name": "White cane",
    "cat": "tech"
  },
  {
    "code": "puerto_rico",
    "char": "🇵🇷",
    "name": "Flag: Puerto Rico",
    "cat": "symbols"
  },
  {
    "code": "punch",
    "char": "👊",
    "name": "Oncoming fist",
    "cat": "people"
  },
  {
    "code": "purple_circle",
    "char": "🟣",
    "name": "Purple circle",
    "cat": "status"
  },
  {
    "code": "purple_heart",
    "char": "💜",
    "name": "Purple heart",
    "cat": "people"
  },
  {
    "code": "purple_square",
    "char": "🟪",
    "name": "Purple square",
    "cat": "symbols"
  },
  {
    "code": "purse",
    "char": "👛",
    "name": "Purse",
    "cat": "tech"
  },
  {
    "code": "pushpin",
    "char": "📌",
    "name": "Pushpin",
    "cat": "tech"
  },
  {
    "code": "put_litter_in_its_place",
    "char": "🚮",
    "name": "Litter in bin sign",
    "cat": "symbols"
  },
  {
    "code": "qatar",
    "char": "🇶🇦",
    "name": "Flag: Qatar",
    "cat": "symbols"
  },
  {
    "code": "question",
    "char": "❓",
    "name": "Red question mark",
    "cat": "status"
  },
  {
    "code": "rabbit",
    "char": "🐰",
    "name": "Rabbit face",
    "cat": "symbols"
  },
  {
    "code": "rabbit2",
    "char": "🐇",
    "name": "Rabbit",
    "cat": "symbols"
  },
  {
    "code": "raccoon",
    "char": "🦝",
    "name": "Raccoon",
    "cat": "symbols"
  },
  {
    "code": "racehorse",
    "char": "🐎",
    "name": "Horse",
    "cat": "symbols"
  },
  {
    "code": "racing_car",
    "char": "🏎",
    "name": "Racing car",
    "cat": "symbols"
  },
  {
    "code": "radio",
    "char": "📻",
    "name": "Radio",
    "cat": "tech"
  },
  {
    "code": "radio_button",
    "char": "🔘",
    "name": "Radio button",
    "cat": "symbols"
  },
  {
    "code": "radioactive",
    "char": "☢",
    "name": "Radioactive",
    "cat": "status"
  },
  {
    "code": "rage",
    "char": "😡",
    "name": "Enraged face",
    "cat": "people"
  },
  {
    "code": "railway_car",
    "char": "🚃",
    "name": "Railway car",
    "cat": "symbols"
  },
  {
    "code": "railway_track",
    "char": "🛤",
    "name": "Railway track",
    "cat": "symbols"
  },
  {
    "code": "rainbow",
    "char": "🌈",
    "name": "Rainbow",
    "cat": "symbols"
  },
  {
    "code": "rainbow_flag",
    "char": "🏳🌈",
    "name": "Rainbow flag",
    "cat": "symbols"
  },
  {
    "code": "raised_back_of_hand",
    "char": "🤚",
    "name": "Raised back of hand",
    "cat": "people"
  },
  {
    "code": "raised_eyebrow",
    "char": "🤨",
    "name": "Face with raised eyebrow",
    "cat": "people"
  },
  {
    "code": "raised_hand",
    "char": "✋",
    "name": "Raised hand",
    "cat": "people"
  },
  {
    "code": "raised_hand_with_fingers_splayed",
    "char": "🖐",
    "name": "Hand with fingers splayed",
    "cat": "people"
  },
  {
    "code": "raised_hands",
    "char": "🙌",
    "name": "Raising hands",
    "cat": "people"
  },
  {
    "code": "raising_hand",
    "char": "🙋",
    "name": "Person raising hand",
    "cat": "people"
  },
  {
    "code": "raising_hand_man",
    "char": "🙋♂",
    "name": "Man raising hand",
    "cat": "people"
  },
  {
    "code": "raising_hand_woman",
    "char": "🙋♀",
    "name": "Woman raising hand",
    "cat": "people"
  },
  {
    "code": "ram",
    "char": "🐏",
    "name": "Ram",
    "cat": "symbols"
  },
  {
    "code": "ramen",
    "char": "🍜",
    "name": "Steaming bowl",
    "cat": "symbols"
  },
  {
    "code": "rat",
    "char": "🐀",
    "name": "Rat",
    "cat": "symbols"
  },
  {
    "code": "razor",
    "char": "🪒",
    "name": "Razor",
    "cat": "tech"
  },
  {
    "code": "receipt",
    "char": "🧾",
    "name": "Receipt",
    "cat": "tech"
  },
  {
    "code": "record_button",
    "char": "⏺",
    "name": "Record button",
    "cat": "symbols"
  },
  {
    "code": "recycle",
    "char": "♻",
    "name": "Recycling symbol",
    "cat": "tech"
  },
  {
    "code": "red_car",
    "char": "🚗",
    "name": "Automobile",
    "cat": "symbols"
  },
  {
    "code": "red_circle",
    "char": "🔴",
    "name": "Red circle",
    "cat": "status"
  },
  {
    "code": "red_envelope",
    "char": "🧧",
    "name": "Red envelope",
    "cat": "symbols"
  },
  {
    "code": "red_haired_man",
    "char": "👨🦰",
    "name": "Man: red hair",
    "cat": "people"
  },
  {
    "code": "red_haired_woman",
    "char": "👩🦰",
    "name": "Woman: red hair",
    "cat": "people"
  },
  {
    "code": "red_square",
    "char": "🟥",
    "name": "Red square",
    "cat": "symbols"
  },
  {
    "code": "registered",
    "char": "®",
    "name": "Registered",
    "cat": "symbols"
  },
  {
    "code": "relaxed",
    "char": "☺",
    "name": "Smiling face",
    "cat": "people"
  },
  {
    "code": "relieved",
    "char": "😌",
    "name": "Relieved face",
    "cat": "people"
  },
  {
    "code": "reminder_ribbon",
    "char": "🎗",
    "name": "Reminder ribbon",
    "cat": "symbols"
  },
  {
    "code": "repeat",
    "char": "🔁",
    "name": "Repeat button",
    "cat": "symbols"
  },
  {
    "code": "repeat_one",
    "char": "🔂",
    "name": "Repeat single button",
    "cat": "symbols"
  },
  {
    "code": "rescue_worker_helmet",
    "char": "⛑",
    "name": "Rescue worker’s helmet",
    "cat": "tech"
  },
  {
    "code": "restroom",
    "char": "🚻",
    "name": "Restroom",
    "cat": "symbols"
  },
  {
    "code": "reunion",
    "char": "🇷🇪",
    "name": "Flag: Réunion",
    "cat": "symbols"
  },
  {
    "code": "revolving_hearts",
    "char": "💞",
    "name": "Revolving hearts",
    "cat": "people"
  },
  {
    "code": "rewind",
    "char": "⏪",
    "name": "Fast reverse button",
    "cat": "symbols"
  },
  {
    "code": "rhinoceros",
    "char": "🦏",
    "name": "Rhinoceros",
    "cat": "symbols"
  },
  {
    "code": "ribbon",
    "char": "🎀",
    "name": "Ribbon",
    "cat": "symbols"
  },
  {
    "code": "rice",
    "char": "🍚",
    "name": "Cooked rice",
    "cat": "symbols"
  },
  {
    "code": "rice_ball",
    "char": "🍙",
    "name": "Rice ball",
    "cat": "symbols"
  },
  {
    "code": "rice_cracker",
    "char": "🍘",
    "name": "Rice cracker",
    "cat": "symbols"
  },
  {
    "code": "rice_scene",
    "char": "🎑",
    "name": "Moon viewing ceremony",
    "cat": "symbols"
  },
  {
    "code": "right_anger_bubble",
    "char": "🗯",
    "name": "Right anger bubble",
    "cat": "people"
  },
  {
    "code": "rightwards_hand",
    "char": "🫱",
    "name": "Rightwards hand",
    "cat": "people"
  },
  {
    "code": "rightwards_pushing_hand",
    "char": "🫸",
    "name": "Rightwards pushing hand",
    "cat": "people"
  },
  {
    "code": "ring",
    "char": "💍",
    "name": "Ring",
    "cat": "tech"
  },
  {
    "code": "ring_buoy",
    "char": "🛟",
    "name": "Ring buoy",
    "cat": "symbols"
  },
  {
    "code": "ringed_planet",
    "char": "🪐",
    "name": "Ringed planet",
    "cat": "symbols"
  },
  {
    "code": "rock",
    "char": "🪨",
    "name": "Rock",
    "cat": "symbols"
  },
  {
    "code": "rofl",
    "char": "🤣",
    "name": "Rolling on the floor laughing",
    "cat": "people"
  },
  {
    "code": "roll_eyes",
    "char": "🙄",
    "name": "Face with rolling eyes",
    "cat": "people"
  },
  {
    "code": "roll_of_paper",
    "char": "🧻",
    "name": "Roll of paper",
    "cat": "tech"
  },
  {
    "code": "roller_coaster",
    "char": "🎢",
    "name": "Roller coaster",
    "cat": "symbols"
  },
  {
    "code": "roller_skate",
    "char": "🛼",
    "name": "Roller skate",
    "cat": "symbols"
  },
  {
    "code": "romania",
    "char": "🇷🇴",
    "name": "Flag: Romania",
    "cat": "symbols"
  },
  {
    "code": "rooster",
    "char": "🐓",
    "name": "Rooster",
    "cat": "symbols"
  },
  {
    "code": "rose",
    "char": "🌹",
    "name": "Rose",
    "cat": "symbols"
  },
  {
    "code": "rosette",
    "char": "🏵",
    "name": "Rosette",
    "cat": "symbols"
  },
  {
    "code": "rotating_light",
    "char": "🚨",
    "name": "Police car light",
    "cat": "symbols"
  },
  {
    "code": "round_pushpin",
    "char": "📍",
    "name": "Round pushpin",
    "cat": "tech"
  },
  {
    "code": "rowboat",
    "char": "🚣",
    "name": "Person rowing boat",
    "cat": "people"
  },
  {
    "code": "rowing_man",
    "char": "🚣♂",
    "name": "Man rowing boat",
    "cat": "people"
  },
  {
    "code": "rowing_woman",
    "char": "🚣♀",
    "name": "Woman rowing boat",
    "cat": "people"
  },
  {
    "code": "ru",
    "char": "🇷🇺",
    "name": "Flag: Russia",
    "cat": "symbols"
  },
  {
    "code": "rugby_football",
    "char": "🏉",
    "name": "Rugby football",
    "cat": "symbols"
  },
  {
    "code": "runner",
    "char": "🏃",
    "name": "Person running",
    "cat": "people"
  },
  {
    "code": "running",
    "char": "🏃",
    "name": "Person running",
    "cat": "people"
  },
  {
    "code": "running_man",
    "char": "🏃♂",
    "name": "Man running",
    "cat": "people"
  },
  {
    "code": "running_shirt_with_sash",
    "char": "🎽",
    "name": "Running shirt",
    "cat": "symbols"
  },
  {
    "code": "running_woman",
    "char": "🏃♀",
    "name": "Woman running",
    "cat": "people"
  },
  {
    "code": "rwanda",
    "char": "🇷🇼",
    "name": "Flag: Rwanda",
    "cat": "symbols"
  },
  {
    "code": "sa",
    "char": "🈂",
    "name": "Japanese “service charge” button",
    "cat": "symbols"
  },
  {
    "code": "safety_pin",
    "char": "🧷",
    "name": "Safety pin",
    "cat": "tech"
  },
  {
    "code": "safety_vest",
    "char": "🦺",
    "name": "Safety vest",
    "cat": "tech"
  },
  {
    "code": "sagittarius",
    "char": "♐",
    "name": "Sagittarius",
    "cat": "symbols"
  },
  {
    "code": "sailboat",
    "char": "⛵",
    "name": "Sailboat",
    "cat": "symbols"
  },
  {
    "code": "sake",
    "char": "🍶",
    "name": "Sake",
    "cat": "symbols"
  },
  {
    "code": "salt",
    "char": "🧂",
    "name": "Salt",
    "cat": "symbols"
  },
  {
    "code": "saluting_face",
    "char": "🫡",
    "name": "Saluting face",
    "cat": "people"
  },
  {
    "code": "samoa",
    "char": "🇼🇸",
    "name": "Flag: Samoa",
    "cat": "symbols"
  },
  {
    "code": "san_marino",
    "char": "🇸🇲",
    "name": "Flag: San Marino",
    "cat": "symbols"
  },
  {
    "code": "sandal",
    "char": "👡",
    "name": "Woman’s sandal",
    "cat": "tech"
  },
  {
    "code": "sandwich",
    "char": "🥪",
    "name": "Sandwich",
    "cat": "symbols"
  },
  {
    "code": "santa",
    "char": "🎅",
    "name": "Santa Claus",
    "cat": "people"
  },
  {
    "code": "sao_tome_principe",
    "char": "🇸🇹",
    "name": "Flag: São Tomé & Príncipe",
    "cat": "symbols"
  },
  {
    "code": "sari",
    "char": "🥻",
    "name": "Sari",
    "cat": "tech"
  },
  {
    "code": "sassy_man",
    "char": "💁♂",
    "name": "Man tipping hand",
    "cat": "people"
  },
  {
    "code": "sassy_woman",
    "char": "💁♀",
    "name": "Woman tipping hand",
    "cat": "people"
  },
  {
    "code": "satellite",
    "char": "📡",
    "name": "Satellite antenna",
    "cat": "tech"
  },
  {
    "code": "satisfied",
    "char": "😆",
    "name": "Grinning squinting face",
    "cat": "people"
  },
  {
    "code": "saudi_arabia",
    "char": "🇸🇦",
    "name": "Flag: Saudi Arabia",
    "cat": "symbols"
  },
  {
    "code": "sauna_man",
    "char": "🧖♂",
    "name": "Man in steamy room",
    "cat": "people"
  },
  {
    "code": "sauna_person",
    "char": "🧖",
    "name": "Person in steamy room",
    "cat": "people"
  },
  {
    "code": "sauna_woman",
    "char": "🧖♀",
    "name": "Woman in steamy room",
    "cat": "people"
  },
  {
    "code": "sauropod",
    "char": "🦕",
    "name": "Sauropod",
    "cat": "symbols"
  },
  {
    "code": "saxophone",
    "char": "🎷",
    "name": "Saxophone",
    "cat": "tech"
  },
  {
    "code": "scarf",
    "char": "🧣",
    "name": "Scarf",
    "cat": "tech"
  },
  {
    "code": "school",
    "char": "🏫",
    "name": "School",
    "cat": "symbols"
  },
  {
    "code": "school_satchel",
    "char": "🎒",
    "name": "Backpack",
    "cat": "tech"
  },
  {
    "code": "scientist",
    "char": "🧑🔬",
    "name": "Scientist",
    "cat": "people"
  },
  {
    "code": "scissors",
    "char": "✂",
    "name": "Scissors",
    "cat": "tech"
  },
  {
    "code": "scorpion",
    "char": "🦂",
    "name": "Scorpion",
    "cat": "symbols"
  },
  {
    "code": "scorpius",
    "char": "♏",
    "name": "Scorpio",
    "cat": "symbols"
  },
  {
    "code": "scotland",
    "char": "🏴󠁧󠁢󠁳󠁣󠁴󠁿",
    "name": "Flag: Scotland",
    "cat": "symbols"
  },
  {
    "code": "scream",
    "char": "😱",
    "name": "Face screaming in fear",
    "cat": "people"
  },
  {
    "code": "scream_cat",
    "char": "🙀",
    "name": "Weary cat",
    "cat": "people"
  },
  {
    "code": "screwdriver",
    "char": "🪛",
    "name": "Screwdriver",
    "cat": "tech"
  },
  {
    "code": "scroll",
    "char": "📜",
    "name": "Scroll",
    "cat": "tech"
  },
  {
    "code": "seal",
    "char": "🦭",
    "name": "Seal",
    "cat": "symbols"
  },
  {
    "code": "seat",
    "char": "💺",
    "name": "Seat",
    "cat": "symbols"
  },
  {
    "code": "secret",
    "char": "㊙",
    "name": "Japanese “secret” button",
    "cat": "symbols"
  },
  {
    "code": "see_no_evil",
    "char": "🙈",
    "name": "See-no-evil monkey",
    "cat": "people"
  },
  {
    "code": "seedling",
    "char": "🌱",
    "name": "Seedling",
    "cat": "symbols"
  },
  {
    "code": "selfie",
    "char": "🤳",
    "name": "Selfie",
    "cat": "people"
  },
  {
    "code": "senegal",
    "char": "🇸🇳",
    "name": "Flag: Senegal",
    "cat": "symbols"
  },
  {
    "code": "serbia",
    "char": "🇷🇸",
    "name": "Flag: Serbia",
    "cat": "symbols"
  },
  {
    "code": "service_dog",
    "char": "🐕🦺",
    "name": "Service dog",
    "cat": "symbols"
  },
  {
    "code": "seven",
    "char": "7⃣",
    "name": "Keycap: 7",
    "cat": "symbols"
  },
  {
    "code": "sewing_needle",
    "char": "🪡",
    "name": "Sewing needle",
    "cat": "symbols"
  },
  {
    "code": "seychelles",
    "char": "🇸🇨",
    "name": "Flag: Seychelles",
    "cat": "symbols"
  },
  {
    "code": "shaking_face",
    "char": "🫨",
    "name": "Shaking face",
    "cat": "people"
  },
  {
    "code": "shallow_pan_of_food",
    "char": "🥘",
    "name": "Shallow pan of food",
    "cat": "symbols"
  },
  {
    "code": "shamrock",
    "char": "☘",
    "name": "Shamrock",
    "cat": "symbols"
  },
  {
    "code": "shark",
    "char": "🦈",
    "name": "Shark",
    "cat": "symbols"
  },
  {
    "code": "shaved_ice",
    "char": "🍧",
    "name": "Shaved ice",
    "cat": "symbols"
  },
  {
    "code": "sheep",
    "char": "🐑",
    "name": "Ewe",
    "cat": "symbols"
  },
  {
    "code": "shell",
    "char": "🐚",
    "name": "Spiral shell",
    "cat": "symbols"
  },
  {
    "code": "shinto_shrine",
    "char": "⛩",
    "name": "Shinto shrine",
    "cat": "symbols"
  },
  {
    "code": "ship",
    "char": "🚢",
    "name": "Ship",
    "cat": "symbols"
  },
  {
    "code": "shirt",
    "char": "👕",
    "name": "T-shirt",
    "cat": "tech"
  },
  {
    "code": "shit",
    "char": "💩",
    "name": "Pile of poo",
    "cat": "people"
  },
  {
    "code": "shoe",
    "char": "👞",
    "name": "Man’s shoe",
    "cat": "tech"
  },
  {
    "code": "shopping",
    "char": "🛍",
    "name": "Shopping bags",
    "cat": "tech"
  },
  {
    "code": "shopping_cart",
    "char": "🛒",
    "name": "Shopping cart",
    "cat": "tech"
  },
  {
    "code": "shorts",
    "char": "🩳",
    "name": "Shorts",
    "cat": "tech"
  },
  {
    "code": "shower",
    "char": "🚿",
    "name": "Shower",
    "cat": "tech"
  },
  {
    "code": "shrimp",
    "char": "🦐",
    "name": "Shrimp",
    "cat": "symbols"
  },
  {
    "code": "shushing_face",
    "char": "🤫",
    "name": "Shushing face",
    "cat": "people"
  },
  {
    "code": "sierra_leone",
    "char": "🇸🇱",
    "name": "Flag: Sierra Leone",
    "cat": "symbols"
  },
  {
    "code": "signal_strength",
    "char": "📶",
    "name": "Antenna bars",
    "cat": "symbols"
  },
  {
    "code": "singapore",
    "char": "🇸🇬",
    "name": "Flag: Singapore",
    "cat": "symbols"
  },
  {
    "code": "singer",
    "char": "🧑🎤",
    "name": "Singer",
    "cat": "people"
  },
  {
    "code": "sint_maarten",
    "char": "🇸🇽",
    "name": "Flag: Sint Maarten",
    "cat": "symbols"
  },
  {
    "code": "six",
    "char": "6⃣",
    "name": "Keycap: 6",
    "cat": "symbols"
  },
  {
    "code": "six_pointed_star",
    "char": "🔯",
    "name": "Dotted six-pointed star",
    "cat": "symbols"
  },
  {
    "code": "skateboard",
    "char": "🛹",
    "name": "Skateboard",
    "cat": "symbols"
  },
  {
    "code": "ski",
    "char": "🎿",
    "name": "Skis",
    "cat": "symbols"
  },
  {
    "code": "skier",
    "char": "⛷",
    "name": "Skier",
    "cat": "people"
  },
  {
    "code": "skull",
    "char": "💀",
    "name": "Skull",
    "cat": "people"
  },
  {
    "code": "skull_and_crossbones",
    "char": "☠",
    "name": "Skull and crossbones",
    "cat": "people"
  },
  {
    "code": "skunk",
    "char": "🦨",
    "name": "Skunk",
    "cat": "symbols"
  },
  {
    "code": "sled",
    "char": "🛷",
    "name": "Sled",
    "cat": "symbols"
  },
  {
    "code": "sleeping",
    "char": "😴",
    "name": "Sleeping face",
    "cat": "people"
  },
  {
    "code": "sleeping_bed",
    "char": "🛌",
    "name": "Person in bed",
    "cat": "people"
  },
  {
    "code": "sleepy",
    "char": "😪",
    "name": "Sleepy face",
    "cat": "people"
  },
  {
    "code": "slightly_frowning_face",
    "char": "🙁",
    "name": "Slightly frowning face",
    "cat": "people"
  },
  {
    "code": "slightly_smiling_face",
    "char": "🙂",
    "name": "Slightly smiling face",
    "cat": "people"
  },
  {
    "code": "slot_machine",
    "char": "🎰",
    "name": "Slot machine",
    "cat": "symbols"
  },
  {
    "code": "sloth",
    "char": "🦥",
    "name": "Sloth",
    "cat": "symbols"
  },
  {
    "code": "slovakia",
    "char": "🇸🇰",
    "name": "Flag: Slovakia",
    "cat": "symbols"
  },
  {
    "code": "slovenia",
    "char": "🇸🇮",
    "name": "Flag: Slovenia",
    "cat": "symbols"
  },
  {
    "code": "small_airplane",
    "char": "🛩",
    "name": "Small airplane",
    "cat": "symbols"
  },
  {
    "code": "small_blue_diamond",
    "char": "🔹",
    "name": "Small blue diamond",
    "cat": "symbols"
  },
  {
    "code": "small_orange_diamond",
    "char": "🔸",
    "name": "Small orange diamond",
    "cat": "symbols"
  },
  {
    "code": "small_red_triangle",
    "char": "🔺",
    "name": "Red triangle pointed up",
    "cat": "symbols"
  },
  {
    "code": "small_red_triangle_down",
    "char": "🔻",
    "name": "Red triangle pointed down",
    "cat": "symbols"
  },
  {
    "code": "smile_cat",
    "char": "😸",
    "name": "Grinning cat with smiling eyes",
    "cat": "people"
  },
  {
    "code": "smiley",
    "char": "😃",
    "name": "Grinning face with big eyes",
    "cat": "people"
  },
  {
    "code": "smiley_cat",
    "char": "😺",
    "name": "Grinning cat",
    "cat": "people"
  },
  {
    "code": "smiling_face_with_tear",
    "char": "🥲",
    "name": "Smiling face with tear",
    "cat": "people"
  },
  {
    "code": "smiling_face_with_three_hearts",
    "char": "🥰",
    "name": "Smiling face with hearts",
    "cat": "people"
  },
  {
    "code": "smiling_imp",
    "char": "😈",
    "name": "Smiling face with horns",
    "cat": "people"
  },
  {
    "code": "smirk",
    "char": "😏",
    "name": "Smirking face",
    "cat": "people"
  },
  {
    "code": "smirk_cat",
    "char": "😼",
    "name": "Cat with wry smile",
    "cat": "people"
  },
  {
    "code": "smoking",
    "char": "🚬",
    "name": "Cigarette",
    "cat": "tech"
  },
  {
    "code": "snail",
    "char": "🐌",
    "name": "Snail",
    "cat": "symbols"
  },
  {
    "code": "snake",
    "char": "🐍",
    "name": "Snake",
    "cat": "symbols"
  },
  {
    "code": "sneezing_face",
    "char": "🤧",
    "name": "Sneezing face",
    "cat": "people"
  },
  {
    "code": "snowboarder",
    "char": "🏂",
    "name": "Snowboarder",
    "cat": "people"
  },
  {
    "code": "snowflake",
    "char": "❄",
    "name": "Snowflake",
    "cat": "symbols"
  },
  {
    "code": "snowman",
    "char": "⛄",
    "name": "Snowman without snow",
    "cat": "symbols"
  },
  {
    "code": "snowman_with_snow",
    "char": "☃",
    "name": "Snowman",
    "cat": "symbols"
  },
  {
    "code": "soap",
    "char": "🧼",
    "name": "Soap",
    "cat": "tech"
  },
  {
    "code": "sob",
    "char": "😭",
    "name": "Loudly crying face",
    "cat": "people"
  },
  {
    "code": "soccer",
    "char": "⚽",
    "name": "Soccer ball",
    "cat": "symbols"
  },
  {
    "code": "socks",
    "char": "🧦",
    "name": "Socks",
    "cat": "tech"
  },
  {
    "code": "softball",
    "char": "🥎",
    "name": "Softball",
    "cat": "symbols"
  },
  {
    "code": "solomon_islands",
    "char": "🇸🇧",
    "name": "Flag: Solomon Islands",
    "cat": "symbols"
  },
  {
    "code": "somalia",
    "char": "🇸🇴",
    "name": "Flag: Somalia",
    "cat": "symbols"
  },
  {
    "code": "soon",
    "char": "🔜",
    "name": "SOON arrow",
    "cat": "symbols"
  },
  {
    "code": "sos",
    "char": "🆘",
    "name": "SOS button",
    "cat": "status"
  },
  {
    "code": "sound",
    "char": "🔉",
    "name": "Speaker medium volume",
    "cat": "tech"
  },
  {
    "code": "south_africa",
    "char": "🇿🇦",
    "name": "Flag: South Africa",
    "cat": "symbols"
  },
  {
    "code": "south_georgia_south_sandwich_islands",
    "char": "🇬🇸",
    "name": "Flag: South Georgia & South Sandwich Islands",
    "cat": "symbols"
  },
  {
    "code": "south_sudan",
    "char": "🇸🇸",
    "name": "Flag: South Sudan",
    "cat": "symbols"
  },
  {
    "code": "space_invader",
    "char": "👾",
    "name": "Alien monster",
    "cat": "people"
  },
  {
    "code": "spades",
    "char": "♠",
    "name": "Spade suit",
    "cat": "symbols"
  },
  {
    "code": "spaghetti",
    "char": "🍝",
    "name": "Spaghetti",
    "cat": "symbols"
  },
  {
    "code": "sparkle",
    "char": "❇",
    "name": "Sparkle",
    "cat": "symbols"
  },
  {
    "code": "sparkler",
    "char": "🎇",
    "name": "Sparkler",
    "cat": "symbols"
  },
  {
    "code": "sparkling_heart",
    "char": "💖",
    "name": "Sparkling heart",
    "cat": "people"
  },
  {
    "code": "speak_no_evil",
    "char": "🙊",
    "name": "Speak-no-evil monkey",
    "cat": "people"
  },
  {
    "code": "speaker",
    "char": "🔈",
    "name": "Speaker low volume",
    "cat": "tech"
  },
  {
    "code": "speaking_head",
    "char": "🗣",
    "name": "Speaking head",
    "cat": "people"
  },
  {
    "code": "speedboat",
    "char": "🚤",
    "name": "Speedboat",
    "cat": "symbols"
  },
  {
    "code": "spider",
    "char": "🕷",
    "name": "Spider",
    "cat": "symbols"
  },
  {
    "code": "spider_web",
    "char": "🕸",
    "name": "Spider web",
    "cat": "symbols"
  },
  {
    "code": "spiral_calendar",
    "char": "🗓",
    "name": "Spiral calendar",
    "cat": "tech"
  },
  {
    "code": "spiral_notepad",
    "char": "🗒",
    "name": "Spiral notepad",
    "cat": "tech"
  },
  {
    "code": "sponge",
    "char": "🧽",
    "name": "Sponge",
    "cat": "tech"
  },
  {
    "code": "spoon",
    "char": "🥄",
    "name": "Spoon",
    "cat": "symbols"
  },
  {
    "code": "squid",
    "char": "🦑",
    "name": "Squid",
    "cat": "symbols"
  },
  {
    "code": "sri_lanka",
    "char": "🇱🇰",
    "name": "Flag: Sri Lanka",
    "cat": "symbols"
  },
  {
    "code": "st_barthelemy",
    "char": "🇧🇱",
    "name": "Flag: St. Barthélemy",
    "cat": "symbols"
  },
  {
    "code": "st_helena",
    "char": "🇸🇭",
    "name": "Flag: St. Helena",
    "cat": "symbols"
  },
  {
    "code": "st_kitts_nevis",
    "char": "🇰🇳",
    "name": "Flag: St. Kitts & Nevis",
    "cat": "symbols"
  },
  {
    "code": "st_lucia",
    "char": "🇱🇨",
    "name": "Flag: St. Lucia",
    "cat": "symbols"
  },
  {
    "code": "st_martin",
    "char": "🇲🇫",
    "name": "Flag: St. Martin",
    "cat": "symbols"
  },
  {
    "code": "st_pierre_miquelon",
    "char": "🇵🇲",
    "name": "Flag: St. Pierre & Miquelon",
    "cat": "symbols"
  },
  {
    "code": "st_vincent_grenadines",
    "char": "🇻🇨",
    "name": "Flag: St. Vincent & Grenadines",
    "cat": "symbols"
  },
  {
    "code": "stadium",
    "char": "🏟",
    "name": "Stadium",
    "cat": "symbols"
  },
  {
    "code": "standing_man",
    "char": "🧍♂",
    "name": "Man standing",
    "cat": "people"
  },
  {
    "code": "standing_person",
    "char": "🧍",
    "name": "Person standing",
    "cat": "people"
  },
  {
    "code": "standing_woman",
    "char": "🧍♀",
    "name": "Woman standing",
    "cat": "people"
  },
  {
    "code": "star",
    "char": "⭐",
    "name": "Star",
    "cat": "symbols"
  },
  {
    "code": "star_and_crescent",
    "char": "☪",
    "name": "Star and crescent",
    "cat": "symbols"
  },
  {
    "code": "star_of_david",
    "char": "✡",
    "name": "Star of David",
    "cat": "symbols"
  },
  {
    "code": "star_struck",
    "char": "🤩",
    "name": "Star-struck",
    "cat": "people"
  },
  {
    "code": "star2",
    "char": "🌟",
    "name": "Glowing star",
    "cat": "symbols"
  },
  {
    "code": "stars",
    "char": "🌠",
    "name": "Shooting star",
    "cat": "symbols"
  },
  {
    "code": "station",
    "char": "🚉",
    "name": "Station",
    "cat": "symbols"
  },
  {
    "code": "statue_of_liberty",
    "char": "🗽",
    "name": "Statue of Liberty",
    "cat": "symbols"
  },
  {
    "code": "steam_locomotive",
    "char": "🚂",
    "name": "Locomotive",
    "cat": "symbols"
  },
  {
    "code": "stethoscope",
    "char": "🩺",
    "name": "Stethoscope",
    "cat": "tech"
  },
  {
    "code": "stew",
    "char": "🍲",
    "name": "Pot of food",
    "cat": "symbols"
  },
  {
    "code": "stop_button",
    "char": "⏹",
    "name": "Stop button",
    "cat": "symbols"
  },
  {
    "code": "stop_sign",
    "char": "🛑",
    "name": "Stop sign",
    "cat": "status"
  },
  {
    "code": "stopwatch",
    "char": "⏱",
    "name": "Stopwatch",
    "cat": "status"
  },
  {
    "code": "straight_ruler",
    "char": "📏",
    "name": "Straight ruler",
    "cat": "tech"
  },
  {
    "code": "strawberry",
    "char": "🍓",
    "name": "Strawberry",
    "cat": "symbols"
  },
  {
    "code": "stuck_out_tongue",
    "char": "😛",
    "name": "Face with tongue",
    "cat": "people"
  },
  {
    "code": "stuck_out_tongue_closed_eyes",
    "char": "😝",
    "name": "Squinting face with tongue",
    "cat": "people"
  },
  {
    "code": "stuck_out_tongue_winking_eye",
    "char": "😜",
    "name": "Winking face with tongue",
    "cat": "people"
  },
  {
    "code": "student",
    "char": "🧑🎓",
    "name": "Student",
    "cat": "people"
  },
  {
    "code": "studio_microphone",
    "char": "🎙",
    "name": "Studio microphone",
    "cat": "tech"
  },
  {
    "code": "stuffed_flatbread",
    "char": "🥙",
    "name": "Stuffed flatbread",
    "cat": "symbols"
  },
  {
    "code": "sudan",
    "char": "🇸🇩",
    "name": "Flag: Sudan",
    "cat": "symbols"
  },
  {
    "code": "sun_behind_large_cloud",
    "char": "🌥",
    "name": "Sun behind large cloud",
    "cat": "symbols"
  },
  {
    "code": "sun_behind_rain_cloud",
    "char": "🌦",
    "name": "Sun behind rain cloud",
    "cat": "symbols"
  },
  {
    "code": "sun_behind_small_cloud",
    "char": "🌤",
    "name": "Sun behind small cloud",
    "cat": "symbols"
  },
  {
    "code": "sun_with_face",
    "char": "🌞",
    "name": "Sun with face",
    "cat": "symbols"
  },
  {
    "code": "sunflower",
    "char": "🌻",
    "name": "Sunflower",
    "cat": "symbols"
  },
  {
    "code": "sunny",
    "char": "☀",
    "name": "Sun",
    "cat": "symbols"
  },
  {
    "code": "sunrise",
    "char": "🌅",
    "name": "Sunrise",
    "cat": "symbols"
  },
  {
    "code": "sunrise_over_mountains",
    "char": "🌄",
    "name": "Sunrise over mountains",
    "cat": "symbols"
  },
  {
    "code": "superhero",
    "char": "🦸",
    "name": "Superhero",
    "cat": "people"
  },
  {
    "code": "superhero_man",
    "char": "🦸♂",
    "name": "Man superhero",
    "cat": "people"
  },
  {
    "code": "superhero_woman",
    "char": "🦸♀",
    "name": "Woman superhero",
    "cat": "people"
  },
  {
    "code": "supervillain",
    "char": "🦹",
    "name": "Supervillain",
    "cat": "people"
  },
  {
    "code": "supervillain_man",
    "char": "🦹♂",
    "name": "Man supervillain",
    "cat": "people"
  },
  {
    "code": "supervillain_woman",
    "char": "🦹♀",
    "name": "Woman supervillain",
    "cat": "people"
  },
  {
    "code": "surfer",
    "char": "🏄",
    "name": "Person surfing",
    "cat": "people"
  },
  {
    "code": "surfing_man",
    "char": "🏄♂",
    "name": "Man surfing",
    "cat": "people"
  },
  {
    "code": "surfing_woman",
    "char": "🏄♀",
    "name": "Woman surfing",
    "cat": "people"
  },
  {
    "code": "suriname",
    "char": "🇸🇷",
    "name": "Flag: Suriname",
    "cat": "symbols"
  },
  {
    "code": "sushi",
    "char": "🍣",
    "name": "Sushi",
    "cat": "symbols"
  },
  {
    "code": "suspension_railway",
    "char": "🚟",
    "name": "Suspension railway",
    "cat": "symbols"
  },
  {
    "code": "svalbard_jan_mayen",
    "char": "🇸🇯",
    "name": "Flag: Svalbard & Jan Mayen",
    "cat": "symbols"
  },
  {
    "code": "swan",
    "char": "🦢",
    "name": "Swan",
    "cat": "symbols"
  },
  {
    "code": "swaziland",
    "char": "🇸🇿",
    "name": "Flag: Eswatini",
    "cat": "symbols"
  },
  {
    "code": "sweat",
    "char": "😓",
    "name": "Downcast face with sweat",
    "cat": "people"
  },
  {
    "code": "sweat_drops",
    "char": "💦",
    "name": "Sweat droplets",
    "cat": "people"
  },
  {
    "code": "sweden",
    "char": "🇸🇪",
    "name": "Flag: Sweden",
    "cat": "symbols"
  },
  {
    "code": "sweet_potato",
    "char": "🍠",
    "name": "Roasted sweet potato",
    "cat": "symbols"
  },
  {
    "code": "swim_brief",
    "char": "🩲",
    "name": "Briefs",
    "cat": "tech"
  },
  {
    "code": "swimmer",
    "char": "🏊",
    "name": "Person swimming",
    "cat": "people"
  },
  {
    "code": "swimming_man",
    "char": "🏊♂",
    "name": "Man swimming",
    "cat": "people"
  },
  {
    "code": "swimming_woman",
    "char": "🏊♀",
    "name": "Woman swimming",
    "cat": "people"
  },
  {
    "code": "switzerland",
    "char": "🇨🇭",
    "name": "Flag: Switzerland",
    "cat": "symbols"
  },
  {
    "code": "symbols",
    "char": "🔣",
    "name": "Input symbols",
    "cat": "symbols"
  },
  {
    "code": "synagogue",
    "char": "🕍",
    "name": "Synagogue",
    "cat": "symbols"
  },
  {
    "code": "syria",
    "char": "🇸🇾",
    "name": "Flag: Syria",
    "cat": "symbols"
  },
  {
    "code": "syringe",
    "char": "💉",
    "name": "Syringe",
    "cat": "tech"
  },
  {
    "code": "t-rex",
    "char": "🦖",
    "name": "T-Rex",
    "cat": "symbols"
  },
  {
    "code": "taco",
    "char": "🌮",
    "name": "Taco",
    "cat": "symbols"
  },
  {
    "code": "taiwan",
    "char": "🇹🇼",
    "name": "Flag: Taiwan",
    "cat": "symbols"
  },
  {
    "code": "tajikistan",
    "char": "🇹🇯",
    "name": "Flag: Tajikistan",
    "cat": "symbols"
  },
  {
    "code": "takeout_box",
    "char": "🥡",
    "name": "Takeout box",
    "cat": "symbols"
  },
  {
    "code": "tamale",
    "char": "🫔",
    "name": "Tamale",
    "cat": "symbols"
  },
  {
    "code": "tanabata_tree",
    "char": "🎋",
    "name": "Tanabata tree",
    "cat": "symbols"
  },
  {
    "code": "tangerine",
    "char": "🍊",
    "name": "Tangerine",
    "cat": "symbols"
  },
  {
    "code": "tanzania",
    "char": "🇹🇿",
    "name": "Flag: Tanzania",
    "cat": "symbols"
  },
  {
    "code": "taurus",
    "char": "♉",
    "name": "Taurus",
    "cat": "symbols"
  },
  {
    "code": "taxi",
    "char": "🚕",
    "name": "Taxi",
    "cat": "symbols"
  },
  {
    "code": "tea",
    "char": "🍵",
    "name": "Teacup without handle",
    "cat": "symbols"
  },
  {
    "code": "teacher",
    "char": "🧑🏫",
    "name": "Teacher",
    "cat": "people"
  },
  {
    "code": "teapot",
    "char": "🫖",
    "name": "Teapot",
    "cat": "symbols"
  },
  {
    "code": "technologist",
    "char": "🧑💻",
    "name": "Technologist",
    "cat": "people"
  },
  {
    "code": "teddy_bear",
    "char": "🧸",
    "name": "Teddy bear",
    "cat": "symbols"
  },
  {
    "code": "telephone",
    "char": "☎",
    "name": "Telephone",
    "cat": "tech"
  },
  {
    "code": "telephone_receiver",
    "char": "📞",
    "name": "Telephone receiver",
    "cat": "tech"
  },
  {
    "code": "telescope",
    "char": "🔭",
    "name": "Telescope",
    "cat": "tech"
  },
  {
    "code": "tennis",
    "char": "🎾",
    "name": "Tennis",
    "cat": "symbols"
  },
  {
    "code": "tent",
    "char": "⛺",
    "name": "Tent",
    "cat": "symbols"
  },
  {
    "code": "test_tube",
    "char": "🧪",
    "name": "Test tube",
    "cat": "tech"
  },
  {
    "code": "thailand",
    "char": "🇹🇭",
    "name": "Flag: Thailand",
    "cat": "symbols"
  },
  {
    "code": "thermometer",
    "char": "🌡",
    "name": "Thermometer",
    "cat": "symbols"
  },
  {
    "code": "thong_sandal",
    "char": "🩴",
    "name": "Thong sandal",
    "cat": "tech"
  },
  {
    "code": "thought_balloon",
    "char": "💭",
    "name": "Thought balloon",
    "cat": "people"
  },
  {
    "code": "thread",
    "char": "🧵",
    "name": "Thread",
    "cat": "symbols"
  },
  {
    "code": "three",
    "char": "3⃣",
    "name": "Keycap: 3",
    "cat": "symbols"
  },
  {
    "code": "thumbsdown",
    "char": "👎",
    "name": "Thumbs down",
    "cat": "people"
  },
  {
    "code": "thumbsup",
    "char": "👍",
    "name": "Thumbs up",
    "cat": "people"
  },
  {
    "code": "ticket",
    "char": "🎫",
    "name": "Ticket",
    "cat": "symbols"
  },
  {
    "code": "tickets",
    "char": "🎟",
    "name": "Admission tickets",
    "cat": "symbols"
  },
  {
    "code": "tiger",
    "char": "🐯",
    "name": "Tiger face",
    "cat": "symbols"
  },
  {
    "code": "tiger2",
    "char": "🐅",
    "name": "Tiger",
    "cat": "symbols"
  },
  {
    "code": "timer_clock",
    "char": "⏲",
    "name": "Timer clock",
    "cat": "status"
  },
  {
    "code": "timor_leste",
    "char": "🇹🇱",
    "name": "Flag: Timor-Leste",
    "cat": "symbols"
  },
  {
    "code": "tipping_hand_man",
    "char": "💁♂",
    "name": "Man tipping hand",
    "cat": "people"
  },
  {
    "code": "tipping_hand_person",
    "char": "💁",
    "name": "Person tipping hand",
    "cat": "people"
  },
  {
    "code": "tipping_hand_woman",
    "char": "💁♀",
    "name": "Woman tipping hand",
    "cat": "people"
  },
  {
    "code": "tired_face",
    "char": "😫",
    "name": "Tired face",
    "cat": "people"
  },
  {
    "code": "tm",
    "char": "™",
    "name": "Trade mark",
    "cat": "symbols"
  },
  {
    "code": "togo",
    "char": "🇹🇬",
    "name": "Flag: Togo",
    "cat": "symbols"
  },
  {
    "code": "toilet",
    "char": "🚽",
    "name": "Toilet",
    "cat": "tech"
  },
  {
    "code": "tokelau",
    "char": "🇹🇰",
    "name": "Flag: Tokelau",
    "cat": "symbols"
  },
  {
    "code": "tokyo_tower",
    "char": "🗼",
    "name": "Tokyo tower",
    "cat": "symbols"
  },
  {
    "code": "tomato",
    "char": "🍅",
    "name": "Tomato",
    "cat": "symbols"
  },
  {
    "code": "tonga",
    "char": "🇹🇴",
    "name": "Flag: Tonga",
    "cat": "symbols"
  },
  {
    "code": "tongue",
    "char": "👅",
    "name": "Tongue",
    "cat": "people"
  },
  {
    "code": "toolbox",
    "char": "🧰",
    "name": "Toolbox",
    "cat": "tech"
  },
  {
    "code": "tooth",
    "char": "🦷",
    "name": "Tooth",
    "cat": "people"
  },
  {
    "code": "toothbrush",
    "char": "🪥",
    "name": "Toothbrush",
    "cat": "tech"
  },
  {
    "code": "top",
    "char": "🔝",
    "name": "TOP arrow",
    "cat": "symbols"
  },
  {
    "code": "tophat",
    "char": "🎩",
    "name": "Top hat",
    "cat": "tech"
  },
  {
    "code": "tornado",
    "char": "🌪",
    "name": "Tornado",
    "cat": "symbols"
  },
  {
    "code": "tr",
    "char": "🇹🇷",
    "name": "Flag: Turkey",
    "cat": "symbols"
  },
  {
    "code": "trackball",
    "char": "🖲",
    "name": "Trackball",
    "cat": "tech"
  },
  {
    "code": "tractor",
    "char": "🚜",
    "name": "Tractor",
    "cat": "symbols"
  },
  {
    "code": "traffic_light",
    "char": "🚥",
    "name": "Horizontal traffic light",
    "cat": "status"
  },
  {
    "code": "train",
    "char": "🚋",
    "name": "Tram car",
    "cat": "symbols"
  },
  {
    "code": "train2",
    "char": "🚆",
    "name": "Train",
    "cat": "symbols"
  },
  {
    "code": "tram",
    "char": "🚊",
    "name": "Tram",
    "cat": "symbols"
  },
  {
    "code": "transgender_flag",
    "char": "🏳⚧",
    "name": "Transgender flag",
    "cat": "symbols"
  },
  {
    "code": "transgender_symbol",
    "char": "⚧",
    "name": "Transgender symbol",
    "cat": "symbols"
  },
  {
    "code": "triangular_flag_on_post",
    "char": "🚩",
    "name": "Triangular flag",
    "cat": "status"
  },
  {
    "code": "triangular_ruler",
    "char": "📐",
    "name": "Triangular ruler",
    "cat": "tech"
  },
  {
    "code": "trident",
    "char": "🔱",
    "name": "Trident emblem",
    "cat": "symbols"
  },
  {
    "code": "trinidad_tobago",
    "char": "🇹🇹",
    "name": "Flag: Trinidad & Tobago",
    "cat": "symbols"
  },
  {
    "code": "tristan_da_cunha",
    "char": "🇹🇦",
    "name": "Flag: Tristan da Cunha",
    "cat": "symbols"
  },
  {
    "code": "triumph",
    "char": "😤",
    "name": "Face with steam from nose",
    "cat": "people"
  },
  {
    "code": "troll",
    "char": "🧌",
    "name": "Troll",
    "cat": "people"
  },
  {
    "code": "trolleybus",
    "char": "🚎",
    "name": "Trolleybus",
    "cat": "symbols"
  },
  {
    "code": "trophy",
    "char": "🏆",
    "name": "Trophy",
    "cat": "symbols"
  },
  {
    "code": "tropical_drink",
    "char": "🍹",
    "name": "Tropical drink",
    "cat": "symbols"
  },
  {
    "code": "tropical_fish",
    "char": "🐠",
    "name": "Tropical fish",
    "cat": "symbols"
  },
  {
    "code": "truck",
    "char": "🚚",
    "name": "Delivery truck",
    "cat": "symbols"
  },
  {
    "code": "trumpet",
    "char": "🎺",
    "name": "Trumpet",
    "cat": "tech"
  },
  {
    "code": "tshirt",
    "char": "👕",
    "name": "T-shirt",
    "cat": "tech"
  },
  {
    "code": "tulip",
    "char": "🌷",
    "name": "Tulip",
    "cat": "symbols"
  },
  {
    "code": "tumbler_glass",
    "char": "🥃",
    "name": "Tumbler glass",
    "cat": "symbols"
  },
  {
    "code": "tunisia",
    "char": "🇹🇳",
    "name": "Flag: Tunisia",
    "cat": "symbols"
  },
  {
    "code": "turkey",
    "char": "🦃",
    "name": "Turkey",
    "cat": "symbols"
  },
  {
    "code": "turkmenistan",
    "char": "🇹🇲",
    "name": "Flag: Turkmenistan",
    "cat": "symbols"
  },
  {
    "code": "turks_caicos_islands",
    "char": "🇹🇨",
    "name": "Flag: Turks & Caicos Islands",
    "cat": "symbols"
  },
  {
    "code": "turtle",
    "char": "🐢",
    "name": "Turtle",
    "cat": "symbols"
  },
  {
    "code": "tuvalu",
    "char": "🇹🇻",
    "name": "Flag: Tuvalu",
    "cat": "symbols"
  },
  {
    "code": "tv",
    "char": "📺",
    "name": "Television",
    "cat": "tech"
  },
  {
    "code": "twisted_rightwards_arrows",
    "char": "🔀",
    "name": "Shuffle tracks button",
    "cat": "symbols"
  },
  {
    "code": "two",
    "char": "2⃣",
    "name": "Keycap: 2",
    "cat": "symbols"
  },
  {
    "code": "two_hearts",
    "char": "💕",
    "name": "Two hearts",
    "cat": "people"
  },
  {
    "code": "two_men_holding_hands",
    "char": "👬",
    "name": "Men holding hands",
    "cat": "people"
  },
  {
    "code": "two_women_holding_hands",
    "char": "👭",
    "name": "Women holding hands",
    "cat": "people"
  },
  {
    "code": "u5272",
    "char": "🈹",
    "name": "Japanese “discount” button",
    "cat": "symbols"
  },
  {
    "code": "u5408",
    "char": "🈴",
    "name": "Japanese “passing grade” button",
    "cat": "symbols"
  },
  {
    "code": "u55b6",
    "char": "🈺",
    "name": "Japanese “open for business” button",
    "cat": "symbols"
  },
  {
    "code": "u6307",
    "char": "🈯",
    "name": "Japanese “reserved” button",
    "cat": "symbols"
  },
  {
    "code": "u6708",
    "char": "🈷",
    "name": "Japanese “monthly amount” button",
    "cat": "symbols"
  },
  {
    "code": "u6709",
    "char": "🈶",
    "name": "Japanese “not free of charge” button",
    "cat": "symbols"
  },
  {
    "code": "u6e80",
    "char": "🈵",
    "name": "Japanese “no vacancy” button",
    "cat": "symbols"
  },
  {
    "code": "u7121",
    "char": "🈚",
    "name": "Japanese “free of charge” button",
    "cat": "symbols"
  },
  {
    "code": "u7533",
    "char": "🈸",
    "name": "Japanese “application” button",
    "cat": "symbols"
  },
  {
    "code": "u7981",
    "char": "🈲",
    "name": "Japanese “prohibited” button",
    "cat": "symbols"
  },
  {
    "code": "u7a7a",
    "char": "🈳",
    "name": "Japanese “vacancy” button",
    "cat": "symbols"
  },
  {
    "code": "uganda",
    "char": "🇺🇬",
    "name": "Flag: Uganda",
    "cat": "symbols"
  },
  {
    "code": "uk",
    "char": "🇬🇧",
    "name": "Flag: United Kingdom",
    "cat": "symbols"
  },
  {
    "code": "ukraine",
    "char": "🇺🇦",
    "name": "Flag: Ukraine",
    "cat": "symbols"
  },
  {
    "code": "umbrella",
    "char": "☔",
    "name": "Umbrella with rain drops",
    "cat": "symbols"
  },
  {
    "code": "unamused",
    "char": "😒",
    "name": "Unamused face",
    "cat": "people"
  },
  {
    "code": "underage",
    "char": "🔞",
    "name": "No one under eighteen",
    "cat": "symbols"
  },
  {
    "code": "unicorn",
    "char": "🦄",
    "name": "Unicorn",
    "cat": "symbols"
  },
  {
    "code": "united_arab_emirates",
    "char": "🇦🇪",
    "name": "Flag: United Arab Emirates",
    "cat": "symbols"
  },
  {
    "code": "united_nations",
    "char": "🇺🇳",
    "name": "Flag: United Nations",
    "cat": "symbols"
  },
  {
    "code": "unlock",
    "char": "🔓",
    "name": "Unlocked",
    "cat": "status"
  },
  {
    "code": "up",
    "char": "🆙",
    "name": "UP! button",
    "cat": "symbols"
  },
  {
    "code": "upside_down_face",
    "char": "🙃",
    "name": "Upside-down face",
    "cat": "people"
  },
  {
    "code": "uruguay",
    "char": "🇺🇾",
    "name": "Flag: Uruguay",
    "cat": "symbols"
  },
  {
    "code": "us",
    "char": "🇺🇸",
    "name": "Flag: United States",
    "cat": "symbols"
  },
  {
    "code": "us_outlying_islands",
    "char": "🇺🇲",
    "name": "Flag: U.S. Outlying Islands",
    "cat": "symbols"
  },
  {
    "code": "us_virgin_islands",
    "char": "🇻🇮",
    "name": "Flag: U.S. Virgin Islands",
    "cat": "symbols"
  },
  {
    "code": "uzbekistan",
    "char": "🇺🇿",
    "name": "Flag: Uzbekistan",
    "cat": "symbols"
  },
  {
    "code": "v",
    "char": "✌",
    "name": "Victory hand",
    "cat": "people"
  },
  {
    "code": "vampire",
    "char": "🧛",
    "name": "Vampire",
    "cat": "people"
  },
  {
    "code": "vampire_man",
    "char": "🧛♂",
    "name": "Man vampire",
    "cat": "people"
  },
  {
    "code": "vampire_woman",
    "char": "🧛♀",
    "name": "Woman vampire",
    "cat": "people"
  },
  {
    "code": "vanuatu",
    "char": "🇻🇺",
    "name": "Flag: Vanuatu",
    "cat": "symbols"
  },
  {
    "code": "vatican_city",
    "char": "🇻🇦",
    "name": "Flag: Vatican City",
    "cat": "symbols"
  },
  {
    "code": "venezuela",
    "char": "🇻🇪",
    "name": "Flag: Venezuela",
    "cat": "symbols"
  },
  {
    "code": "vertical_traffic_light",
    "char": "🚦",
    "name": "Vertical traffic light",
    "cat": "symbols"
  },
  {
    "code": "vhs",
    "char": "📼",
    "name": "Videocassette",
    "cat": "tech"
  },
  {
    "code": "vibration_mode",
    "char": "📳",
    "name": "Vibration mode",
    "cat": "symbols"
  },
  {
    "code": "video_camera",
    "char": "📹",
    "name": "Video camera",
    "cat": "tech"
  },
  {
    "code": "video_game",
    "char": "🎮",
    "name": "Video game",
    "cat": "symbols"
  },
  {
    "code": "vietnam",
    "char": "🇻🇳",
    "name": "Flag: Vietnam",
    "cat": "symbols"
  },
  {
    "code": "violin",
    "char": "🎻",
    "name": "Violin",
    "cat": "tech"
  },
  {
    "code": "virgo",
    "char": "♍",
    "name": "Virgo",
    "cat": "symbols"
  },
  {
    "code": "volcano",
    "char": "🌋",
    "name": "Volcano",
    "cat": "symbols"
  },
  {
    "code": "volleyball",
    "char": "🏐",
    "name": "Volleyball",
    "cat": "symbols"
  },
  {
    "code": "vomiting_face",
    "char": "🤮",
    "name": "Face vomiting",
    "cat": "people"
  },
  {
    "code": "vs",
    "char": "🆚",
    "name": "VS button",
    "cat": "symbols"
  },
  {
    "code": "vulcan_salute",
    "char": "🖖",
    "name": "Vulcan salute",
    "cat": "people"
  },
  {
    "code": "waffle",
    "char": "🧇",
    "name": "Waffle",
    "cat": "symbols"
  },
  {
    "code": "wales",
    "char": "🏴󠁧󠁢󠁷󠁬󠁳󠁿",
    "name": "Flag: Wales",
    "cat": "symbols"
  },
  {
    "code": "walking",
    "char": "🚶",
    "name": "Person walking",
    "cat": "people"
  },
  {
    "code": "walking_man",
    "char": "🚶♂",
    "name": "Man walking",
    "cat": "people"
  },
  {
    "code": "walking_woman",
    "char": "🚶♀",
    "name": "Woman walking",
    "cat": "people"
  },
  {
    "code": "wallis_futuna",
    "char": "🇼🇫",
    "name": "Flag: Wallis & Futuna",
    "cat": "symbols"
  },
  {
    "code": "waning_crescent_moon",
    "char": "🌘",
    "name": "Waning crescent moon",
    "cat": "symbols"
  },
  {
    "code": "waning_gibbous_moon",
    "char": "🌖",
    "name": "Waning gibbous moon",
    "cat": "symbols"
  },
  {
    "code": "wastebasket",
    "char": "🗑",
    "name": "Wastebasket",
    "cat": "tech"
  },
  {
    "code": "watch",
    "char": "⌚",
    "name": "Watch",
    "cat": "symbols"
  },
  {
    "code": "water_buffalo",
    "char": "🐃",
    "name": "Water buffalo",
    "cat": "symbols"
  },
  {
    "code": "water_polo",
    "char": "🤽",
    "name": "Person playing water polo",
    "cat": "people"
  },
  {
    "code": "watermelon",
    "char": "🍉",
    "name": "Watermelon",
    "cat": "symbols"
  },
  {
    "code": "wavy_dash",
    "char": "〰",
    "name": "Wavy dash",
    "cat": "symbols"
  },
  {
    "code": "waxing_crescent_moon",
    "char": "🌒",
    "name": "Waxing crescent moon",
    "cat": "symbols"
  },
  {
    "code": "waxing_gibbous_moon",
    "char": "🌔",
    "name": "Waxing gibbous moon",
    "cat": "symbols"
  },
  {
    "code": "wc",
    "char": "🚾",
    "name": "Water closet",
    "cat": "symbols"
  },
  {
    "code": "weary",
    "char": "😩",
    "name": "Weary face",
    "cat": "people"
  },
  {
    "code": "wedding",
    "char": "💒",
    "name": "Wedding",
    "cat": "symbols"
  },
  {
    "code": "weight_lifting",
    "char": "🏋",
    "name": "Person lifting weights",
    "cat": "people"
  },
  {
    "code": "weight_lifting_man",
    "char": "🏋♂",
    "name": "Man lifting weights",
    "cat": "people"
  },
  {
    "code": "weight_lifting_woman",
    "char": "🏋♀",
    "name": "Woman lifting weights",
    "cat": "people"
  },
  {
    "code": "western_sahara",
    "char": "🇪🇭",
    "name": "Flag: Western Sahara",
    "cat": "symbols"
  },
  {
    "code": "whale",
    "char": "🐳",
    "name": "Spouting whale",
    "cat": "symbols"
  },
  {
    "code": "whale2",
    "char": "🐋",
    "name": "Whale",
    "cat": "symbols"
  },
  {
    "code": "wheel",
    "char": "🛞",
    "name": "Wheel",
    "cat": "symbols"
  },
  {
    "code": "wheel_of_dharma",
    "char": "☸",
    "name": "Wheel of dharma",
    "cat": "symbols"
  },
  {
    "code": "wheelchair",
    "char": "♿",
    "name": "Wheelchair symbol",
    "cat": "symbols"
  },
  {
    "code": "white_check_mark",
    "char": "✅",
    "name": "Check mark button",
    "cat": "status"
  },
  {
    "code": "white_circle",
    "char": "⚪",
    "name": "White circle",
    "cat": "status"
  },
  {
    "code": "white_flag",
    "char": "🏳",
    "name": "White flag",
    "cat": "symbols"
  },
  {
    "code": "white_flower",
    "char": "💮",
    "name": "White flower",
    "cat": "symbols"
  },
  {
    "code": "white_haired_man",
    "char": "👨🦳",
    "name": "Man: white hair",
    "cat": "people"
  },
  {
    "code": "white_haired_woman",
    "char": "👩🦳",
    "name": "Woman: white hair",
    "cat": "people"
  },
  {
    "code": "white_heart",
    "char": "🤍",
    "name": "White heart",
    "cat": "people"
  },
  {
    "code": "white_large_square",
    "char": "⬜",
    "name": "White large square",
    "cat": "symbols"
  },
  {
    "code": "white_medium_small_square",
    "char": "◽",
    "name": "White medium-small square",
    "cat": "symbols"
  },
  {
    "code": "white_medium_square",
    "char": "◻",
    "name": "White medium square",
    "cat": "symbols"
  },
  {
    "code": "white_small_square",
    "char": "▫",
    "name": "White small square",
    "cat": "symbols"
  },
  {
    "code": "white_square_button",
    "char": "🔳",
    "name": "White square button",
    "cat": "symbols"
  },
  {
    "code": "wilted_flower",
    "char": "🥀",
    "name": "Wilted flower",
    "cat": "symbols"
  },
  {
    "code": "wind_chime",
    "char": "🎐",
    "name": "Wind chime",
    "cat": "symbols"
  },
  {
    "code": "wind_face",
    "char": "🌬",
    "name": "Wind face",
    "cat": "symbols"
  },
  {
    "code": "window",
    "char": "🪟",
    "name": "Window",
    "cat": "tech"
  },
  {
    "code": "wine_glass",
    "char": "🍷",
    "name": "Wine glass",
    "cat": "symbols"
  },
  {
    "code": "wing",
    "char": "🪽",
    "name": "Wing",
    "cat": "symbols"
  },
  {
    "code": "wink",
    "char": "😉",
    "name": "Winking face",
    "cat": "people"
  },
  {
    "code": "wireless",
    "char": "🛜",
    "name": "Wireless",
    "cat": "symbols"
  },
  {
    "code": "wolf",
    "char": "🐺",
    "name": "Wolf",
    "cat": "symbols"
  },
  {
    "code": "woman",
    "char": "👩",
    "name": "Woman",
    "cat": "people"
  },
  {
    "code": "woman_artist",
    "char": "👩🎨",
    "name": "Woman artist",
    "cat": "people"
  },
  {
    "code": "woman_astronaut",
    "char": "👩🚀",
    "name": "Woman astronaut",
    "cat": "people"
  },
  {
    "code": "woman_beard",
    "char": "🧔♀",
    "name": "Woman: beard",
    "cat": "people"
  },
  {
    "code": "woman_cartwheeling",
    "char": "🤸♀",
    "name": "Woman cartwheeling",
    "cat": "people"
  },
  {
    "code": "woman_cook",
    "char": "👩🍳",
    "name": "Woman cook",
    "cat": "people"
  },
  {
    "code": "woman_dancing",
    "char": "💃",
    "name": "Woman dancing",
    "cat": "people"
  },
  {
    "code": "woman_facepalming",
    "char": "🤦♀",
    "name": "Woman facepalming",
    "cat": "people"
  },
  {
    "code": "woman_factory_worker",
    "char": "👩🏭",
    "name": "Woman factory worker",
    "cat": "people"
  },
  {
    "code": "woman_farmer",
    "char": "👩🌾",
    "name": "Woman farmer",
    "cat": "people"
  },
  {
    "code": "woman_feeding_baby",
    "char": "👩🍼",
    "name": "Woman feeding baby",
    "cat": "people"
  },
  {
    "code": "woman_firefighter",
    "char": "👩🚒",
    "name": "Woman firefighter",
    "cat": "people"
  },
  {
    "code": "woman_health_worker",
    "char": "👩⚕",
    "name": "Woman health worker",
    "cat": "people"
  },
  {
    "code": "woman_in_manual_wheelchair",
    "char": "👩🦽",
    "name": "Woman in manual wheelchair",
    "cat": "people"
  },
  {
    "code": "woman_in_motorized_wheelchair",
    "char": "👩🦼",
    "name": "Woman in motorized wheelchair",
    "cat": "people"
  },
  {
    "code": "woman_in_tuxedo",
    "char": "🤵♀",
    "name": "Woman in tuxedo",
    "cat": "people"
  },
  {
    "code": "woman_judge",
    "char": "👩⚖",
    "name": "Woman judge",
    "cat": "people"
  },
  {
    "code": "woman_juggling",
    "char": "🤹♀",
    "name": "Woman juggling",
    "cat": "people"
  },
  {
    "code": "woman_mechanic",
    "char": "👩🔧",
    "name": "Woman mechanic",
    "cat": "people"
  },
  {
    "code": "woman_office_worker",
    "char": "👩💼",
    "name": "Woman office worker",
    "cat": "people"
  },
  {
    "code": "woman_pilot",
    "char": "👩✈",
    "name": "Woman pilot",
    "cat": "people"
  },
  {
    "code": "woman_playing_handball",
    "char": "🤾♀",
    "name": "Woman playing handball",
    "cat": "people"
  },
  {
    "code": "woman_playing_water_polo",
    "char": "🤽♀",
    "name": "Woman playing water polo",
    "cat": "people"
  },
  {
    "code": "woman_scientist",
    "char": "👩🔬",
    "name": "Woman scientist",
    "cat": "people"
  },
  {
    "code": "woman_shrugging",
    "char": "🤷♀",
    "name": "Woman shrugging",
    "cat": "people"
  },
  {
    "code": "woman_singer",
    "char": "👩🎤",
    "name": "Woman singer",
    "cat": "people"
  },
  {
    "code": "woman_student",
    "char": "👩🎓",
    "name": "Woman student",
    "cat": "people"
  },
  {
    "code": "woman_teacher",
    "char": "👩🏫",
    "name": "Woman teacher",
    "cat": "people"
  },
  {
    "code": "woman_technologist",
    "char": "👩💻",
    "name": "Woman technologist",
    "cat": "people"
  },
  {
    "code": "woman_with_headscarf",
    "char": "🧕",
    "name": "Woman with headscarf",
    "cat": "people"
  },
  {
    "code": "woman_with_probing_cane",
    "char": "👩🦯",
    "name": "Woman with white cane",
    "cat": "people"
  },
  {
    "code": "woman_with_turban",
    "char": "👳♀",
    "name": "Woman wearing turban",
    "cat": "people"
  },
  {
    "code": "woman_with_veil",
    "char": "👰♀",
    "name": "Woman with veil",
    "cat": "people"
  },
  {
    "code": "womans_clothes",
    "char": "👚",
    "name": "Woman’s clothes",
    "cat": "tech"
  },
  {
    "code": "womans_hat",
    "char": "👒",
    "name": "Woman’s hat",
    "cat": "tech"
  },
  {
    "code": "women_wrestling",
    "char": "🤼♀",
    "name": "Women wrestling",
    "cat": "people"
  },
  {
    "code": "womens",
    "char": "🚺",
    "name": "Women’s room",
    "cat": "symbols"
  },
  {
    "code": "wood",
    "char": "🪵",
    "name": "Wood",
    "cat": "symbols"
  },
  {
    "code": "woozy_face",
    "char": "🥴",
    "name": "Woozy face",
    "cat": "people"
  },
  {
    "code": "world_map",
    "char": "🗺",
    "name": "World map",
    "cat": "symbols"
  },
  {
    "code": "worm",
    "char": "🪱",
    "name": "Worm",
    "cat": "symbols"
  },
  {
    "code": "worried",
    "char": "😟",
    "name": "Worried face",
    "cat": "people"
  },
  {
    "code": "wrestling",
    "char": "🤼",
    "name": "People wrestling",
    "cat": "people"
  },
  {
    "code": "writing_hand",
    "char": "✍",
    "name": "Writing hand",
    "cat": "people"
  },
  {
    "code": "x_ray",
    "char": "🩻",
    "name": "X-ray",
    "cat": "tech"
  },
  {
    "code": "yarn",
    "char": "🧶",
    "name": "Yarn",
    "cat": "symbols"
  },
  {
    "code": "yawning_face",
    "char": "🥱",
    "name": "Yawning face",
    "cat": "people"
  },
  {
    "code": "yellow_circle",
    "char": "🟡",
    "name": "Yellow circle",
    "cat": "status"
  },
  {
    "code": "yellow_heart",
    "char": "💛",
    "name": "Yellow heart",
    "cat": "people"
  },
  {
    "code": "yellow_square",
    "char": "🟨",
    "name": "Yellow square",
    "cat": "symbols"
  },
  {
    "code": "yemen",
    "char": "🇾🇪",
    "name": "Flag: Yemen",
    "cat": "symbols"
  },
  {
    "code": "yen",
    "char": "💴",
    "name": "Yen banknote",
    "cat": "tech"
  },
  {
    "code": "yin_yang",
    "char": "☯",
    "name": "Yin yang",
    "cat": "symbols"
  },
  {
    "code": "yo_yo",
    "char": "🪀",
    "name": "Yo-yo",
    "cat": "symbols"
  },
  {
    "code": "yum",
    "char": "😋",
    "name": "Face savoring food",
    "cat": "people"
  },
  {
    "code": "zambia",
    "char": "🇿🇲",
    "name": "Flag: Zambia",
    "cat": "symbols"
  },
  {
    "code": "zany_face",
    "char": "🤪",
    "name": "Zany face",
    "cat": "people"
  },
  {
    "code": "zap",
    "char": "⚡",
    "name": "High voltage",
    "cat": "status"
  },
  {
    "code": "zebra",
    "char": "🦓",
    "name": "Zebra",
    "cat": "symbols"
  },
  {
    "code": "zero",
    "char": "0⃣",
    "name": "Keycap: 0",
    "cat": "symbols"
  },
  {
    "code": "zimbabwe",
    "char": "🇿🇼",
    "name": "Flag: Zimbabwe",
    "cat": "symbols"
  },
  {
    "code": "zipper_mouth_face",
    "char": "🤐",
    "name": "Zipper-mouth face",
    "cat": "people"
  },
  {
    "code": "zombie",
    "char": "🧟",
    "name": "Zombie",
    "cat": "people"
  },
  {
    "code": "zombie_man",
    "char": "🧟♂",
    "name": "Man zombie",
    "cat": "people"
  },
  {
    "code": "zombie_woman",
    "char": "🧟♀",
    "name": "Woman zombie",
    "cat": "people"
  },
  {
    "code": "zzz",
    "char": "💤",
    "name": "ZZZ",
    "cat": "people"
  }
];

  const GITHUB_EMOJI_MAP = {
  "100": "💯",
  "1234": "🔢",
  "octocat": "<img class=\"emoji\" src=\"https://github.githubassets.com/images/icons/emoji/octocat.png?v8\" width=\"20\" height=\"20\" alt=\":octocat:\" style=\"vertical-align: -3px; display: inline-block;\">",
  "shipit": "<img class=\"emoji\" src=\"https://github.githubassets.com/images/icons/emoji/shipit.png?v8\" width=\"20\" height=\"20\" alt=\":shipit:\" style=\"vertical-align: -3px; display: inline-block;\">",
  "copilot": "<img class=\"emoji\" src=\"https://github.githubassets.com/images/icons/emoji/copilot.png?v8\" width=\"20\" height=\"20\" alt=\":copilot:\" style=\"vertical-align: -3px; display: inline-block;\">",
  "dependabot": "<img class=\"emoji\" src=\"https://github.githubassets.com/images/icons/emoji/dependabot.png?v8\" width=\"20\" height=\"20\" alt=\":dependabot:\" style=\"vertical-align: -3px; display: inline-block;\">",
  "bowtie": "<img class=\"emoji\" src=\"https://github.githubassets.com/images/icons/emoji/bowtie.png?v8\" width=\"20\" height=\"20\" alt=\":bowtie:\" style=\"vertical-align: -3px; display: inline-block;\">",
  "feelsgood": "<img class=\"emoji\" src=\"https://github.githubassets.com/images/icons/emoji/feelsgood.png?v8\" width=\"20\" height=\"20\" alt=\":feelsgood:\" style=\"vertical-align: -3px; display: inline-block;\">",
  "finnadie": "<img class=\"emoji\" src=\"https://github.githubassets.com/images/icons/emoji/finnadie.png?v8\" width=\"20\" height=\"20\" alt=\":finnadie:\" style=\"vertical-align: -3px; display: inline-block;\">",
  "fishsticks": "<img class=\"emoji\" src=\"https://github.githubassets.com/images/icons/emoji/fishsticks.png?v8\" width=\"20\" height=\"20\" alt=\":fishsticks:\" style=\"vertical-align: -3px; display: inline-block;\">",
  "goberserk": "<img class=\"emoji\" src=\"https://github.githubassets.com/images/icons/emoji/goberserk.png?v8\" width=\"20\" height=\"20\" alt=\":goberserk:\" style=\"vertical-align: -3px; display: inline-block;\">",
  "godmode": "<img class=\"emoji\" src=\"https://github.githubassets.com/images/icons/emoji/godmode.png?v8\" width=\"20\" height=\"20\" alt=\":godmode:\" style=\"vertical-align: -3px; display: inline-block;\">",
  "hurtrealbad": "<img class=\"emoji\" src=\"https://github.githubassets.com/images/icons/emoji/hurtrealbad.png?v8\" width=\"20\" height=\"20\" alt=\":hurtrealbad:\" style=\"vertical-align: -3px; display: inline-block;\">",
  "neckbeard": "<img class=\"emoji\" src=\"https://github.githubassets.com/images/icons/emoji/neckbeard.png?v8\" width=\"20\" height=\"20\" alt=\":neckbeard:\" style=\"vertical-align: -3px; display: inline-block;\">",
  "rage1": "<img class=\"emoji\" src=\"https://github.githubassets.com/images/icons/emoji/rage1.png?v8\" width=\"20\" height=\"20\" alt=\":rage1:\" style=\"vertical-align: -3px; display: inline-block;\">",
  "rage2": "<img class=\"emoji\" src=\"https://github.githubassets.com/images/icons/emoji/rage2.png?v8\" width=\"20\" height=\"20\" alt=\":rage2:\" style=\"vertical-align: -3px; display: inline-block;\">",
  "rage3": "<img class=\"emoji\" src=\"https://github.githubassets.com/images/icons/emoji/rage3.png?v8\" width=\"20\" height=\"20\" alt=\":rage3:\" style=\"vertical-align: -3px; display: inline-block;\">",
  "rage4": "<img class=\"emoji\" src=\"https://github.githubassets.com/images/icons/emoji/rage4.png?v8\" width=\"20\" height=\"20\" alt=\":rage4:\" style=\"vertical-align: -3px; display: inline-block;\">",
  "suspect": "<img class=\"emoji\" src=\"https://github.githubassets.com/images/icons/emoji/suspect.png?v8\" width=\"20\" height=\"20\" alt=\":suspect:\" style=\"vertical-align: -3px; display: inline-block;\">",
  "trollface": "<img class=\"emoji\" src=\"https://github.githubassets.com/images/icons/emoji/trollface.png?v8\" width=\"20\" height=\"20\" alt=\":trollface:\" style=\"vertical-align: -3px; display: inline-block;\">",
  "atom": "<img class=\"emoji\" src=\"https://github.githubassets.com/images/icons/emoji/atom.png?v8\" width=\"20\" height=\"20\" alt=\":atom:\" style=\"vertical-align: -3px; display: inline-block;\">",
  "electron": "<img class=\"emoji\" src=\"https://github.githubassets.com/images/icons/emoji/electron.png?v8\" width=\"20\" height=\"20\" alt=\":electron:\" style=\"vertical-align: -3px; display: inline-block;\">",
  "basecamp": "<img class=\"emoji\" src=\"https://github.githubassets.com/images/icons/emoji/basecamp.png?v8\" width=\"20\" height=\"20\" alt=\":basecamp:\" style=\"vertical-align: -3px; display: inline-block;\">",
  "basecampy": "<img class=\"emoji\" src=\"https://github.githubassets.com/images/icons/emoji/basecampy.png?v8\" width=\"20\" height=\"20\" alt=\":basecampy:\" style=\"vertical-align: -3px; display: inline-block;\">",
  "accessibility": "<img class=\"emoji\" src=\"https://github.githubassets.com/images/icons/emoji/accessibility.png?v8\" width=\"20\" height=\"20\" alt=\":accessibility:\" style=\"vertical-align: -3px; display: inline-block;\">",
  "+1": "👍",
  "-1": "👎",
  "tada": "🎉",
  "rocket": "🚀",
  "bug": "🐛",
  "sparkles": "✨",
  "fire": "🔥",
  "eyes": "👀",
  "memo": "📝",
  "heavy_check_mark": "✔",
  "x": "❌",
  "warning": "⚠",
  "lock": "🔒",
  "key": "🔑",
  "shield": "🛡",
  "computer": "💻",
  "package": "📦",
  "gear": "⚙",
  "wrench": "🔧",
  "robot": "🤖",
  "heart": "❤",
  "thinking": "🤔",
  "clap": "👏",
  "wave": "👋",
  "pray": "🙏",
  "muscle": "💪",
  "smile": "😄",
  "grin": "😁",
  "joy": "😂",
  "sweat_smile": "😅",
  "sunglasses": "😎",
  "nerd_face": "🤓",
  "facepalm": "🤦",
  "shrug": "🤷",
  "exploding_head": "🤯",
  "checkered_flag": "🏁",
  "speech_balloon": "💬",
  "1st_place_medal": "🥇",
  "2nd_place_medal": "🥈",
  "3rd_place_medal": "🥉",
  "8ball": "🎱",
  "a": "🅰",
  "ab": "🆎",
  "abacus": "🧮",
  "abc": "🔤",
  "abcd": "🔡",
  "accept": "🉑",
  "accordion": "🪗",
  "adhesive_bandage": "🩹",
  "adult": "🧑",
  "aerial_tramway": "🚡",
  "afghanistan": "🇦🇫",
  "airplane": "✈",
  "aland_islands": "🇦🇽",
  "alarm_clock": "⏰",
  "albania": "🇦🇱",
  "alembic": "⚗",
  "algeria": "🇩🇿",
  "alien": "👽",
  "ambulance": "🚑",
  "american_samoa": "🇦🇸",
  "amphora": "🏺",
  "anatomical_heart": "🫀",
  "anchor": "⚓",
  "andorra": "🇦🇩",
  "angel": "👼",
  "anger": "💢",
  "angola": "🇦🇴",
  "angry": "😠",
  "anguilla": "🇦🇮",
  "anguished": "😧",
  "ant": "🐜",
  "antarctica": "🇦🇶",
  "antigua_barbuda": "🇦🇬",
  "apple": "🍎",
  "aquarius": "♒",
  "argentina": "🇦🇷",
  "aries": "♈",
  "armenia": "🇦🇲",
  "arrow_backward": "◀",
  "arrow_double_down": "⏬",
  "arrow_double_up": "⏫",
  "arrow_down": "⬇",
  "arrow_down_small": "🔽",
  "arrow_forward": "▶",
  "arrow_heading_down": "⤵",
  "arrow_heading_up": "⤴",
  "arrow_left": "⬅",
  "arrow_lower_left": "↙",
  "arrow_lower_right": "↘",
  "arrow_right": "➡",
  "arrow_right_hook": "↪",
  "arrow_up": "⬆",
  "arrow_up_down": "↕",
  "arrow_up_small": "🔼",
  "arrow_upper_left": "↖",
  "arrow_upper_right": "↗",
  "arrows_clockwise": "🔃",
  "arrows_counterclockwise": "🔄",
  "art": "🎨",
  "articulated_lorry": "🚛",
  "artificial_satellite": "🛰",
  "artist": "🧑🎨",
  "aruba": "🇦🇼",
  "ascension_island": "🇦🇨",
  "asterisk": "*⃣",
  "astonished": "😲",
  "astronaut": "🧑🚀",
  "athletic_shoe": "👟",
  "atm": "🏧",
  "atom_symbol": "⚛",
  "australia": "🇦🇺",
  "austria": "🇦🇹",
  "auto_rickshaw": "🛺",
  "avocado": "🥑",
  "axe": "🪓",
  "azerbaijan": "🇦🇿",
  "b": "🅱",
  "baby": "👶",
  "baby_bottle": "🍼",
  "baby_chick": "🐤",
  "baby_symbol": "🚼",
  "back": "🔙",
  "bacon": "🥓",
  "badger": "🦡",
  "badminton": "🏸",
  "bagel": "🥯",
  "baggage_claim": "🛄",
  "baguette_bread": "🥖",
  "bahamas": "🇧🇸",
  "bahrain": "🇧🇭",
  "balance_scale": "⚖",
  "bald_man": "👨🦲",
  "bald_woman": "👩🦲",
  "ballet_shoes": "🩰",
  "balloon": "🎈",
  "ballot_box": "🗳",
  "ballot_box_with_check": "☑",
  "bamboo": "🎍",
  "banana": "🍌",
  "bangbang": "‼",
  "bangladesh": "🇧🇩",
  "banjo": "🪕",
  "bank": "🏦",
  "bar_chart": "📊",
  "barbados": "🇧🇧",
  "barber": "💈",
  "baseball": "⚾",
  "basket": "🧺",
  "basketball": "🏀",
  "basketball_man": "⛹♂",
  "basketball_woman": "⛹♀",
  "bat": "🦇",
  "bath": "🛀",
  "bathtub": "🛁",
  "battery": "🔋",
  "beach_umbrella": "🏖",
  "beans": "🫘",
  "bear": "🐻",
  "bearded_person": "🧔",
  "beaver": "🦫",
  "bed": "🛏",
  "bee": "🐝",
  "beer": "🍺",
  "beers": "🍻",
  "beetle": "🪲",
  "beginner": "🔰",
  "belarus": "🇧🇾",
  "belgium": "🇧🇪",
  "belize": "🇧🇿",
  "bell": "🔔",
  "bell_pepper": "🫑",
  "bellhop_bell": "🛎",
  "benin": "🇧🇯",
  "bento": "🍱",
  "bermuda": "🇧🇲",
  "beverage_box": "🧃",
  "bhutan": "🇧🇹",
  "bicyclist": "🚴",
  "bike": "🚲",
  "biking_man": "🚴♂",
  "biking_woman": "🚴♀",
  "bikini": "👙",
  "billed_cap": "🧢",
  "biohazard": "☣",
  "bird": "🐦",
  "birthday": "🎂",
  "bison": "🦬",
  "biting_lip": "🫦",
  "black_bird": "🐦⬛",
  "black_cat": "🐈⬛",
  "black_circle": "⚫",
  "black_flag": "🏴",
  "black_heart": "🖤",
  "black_joker": "🃏",
  "black_large_square": "⬛",
  "black_medium_small_square": "◾",
  "black_medium_square": "◼",
  "black_nib": "✒",
  "black_small_square": "▪",
  "black_square_button": "🔲",
  "blond_haired_man": "👱♂",
  "blond_haired_person": "👱",
  "blond_haired_woman": "👱♀",
  "blonde_woman": "👱♀",
  "blossom": "🌼",
  "blowfish": "🐡",
  "blue_book": "📘",
  "blue_car": "🚙",
  "blue_heart": "💙",
  "blue_square": "🟦",
  "blueberries": "🫐",
  "blush": "😊",
  "boar": "🐗",
  "boat": "⛵",
  "bolivia": "🇧🇴",
  "bomb": "💣",
  "bone": "🦴",
  "book": "📖",
  "bookmark": "🔖",
  "bookmark_tabs": "📑",
  "books": "📚",
  "boom": "💥",
  "boomerang": "🪃",
  "boot": "👢",
  "bosnia_herzegovina": "🇧🇦",
  "botswana": "🇧🇼",
  "bouncing_ball_man": "⛹♂",
  "bouncing_ball_person": "⛹",
  "bouncing_ball_woman": "⛹♀",
  "bouquet": "💐",
  "bouvet_island": "🇧🇻",
  "bow": "🙇",
  "bow_and_arrow": "🏹",
  "bowing_man": "🙇♂",
  "bowing_woman": "🙇♀",
  "bowl_with_spoon": "🥣",
  "bowling": "🎳",
  "boxing_glove": "🥊",
  "boy": "👦",
  "brain": "🧠",
  "brazil": "🇧🇷",
  "bread": "🍞",
  "breast_feeding": "🤱",
  "bricks": "🧱",
  "bride_with_veil": "👰♀",
  "bridge_at_night": "🌉",
  "briefcase": "💼",
  "british_indian_ocean_territory": "🇮🇴",
  "british_virgin_islands": "🇻🇬",
  "broccoli": "🥦",
  "broken_heart": "💔",
  "broom": "🧹",
  "brown_circle": "🟤",
  "brown_heart": "🤎",
  "brown_square": "🟫",
  "brunei": "🇧🇳",
  "bubble_tea": "🧋",
  "bubbles": "🫧",
  "bucket": "🪣",
  "building_construction": "🏗",
  "bulb": "💡",
  "bulgaria": "🇧🇬",
  "bullettrain_front": "🚅",
  "bullettrain_side": "🚄",
  "burkina_faso": "🇧🇫",
  "burrito": "🌯",
  "burundi": "🇧🇮",
  "bus": "🚌",
  "business_suit_levitating": "🕴",
  "busstop": "🚏",
  "bust_in_silhouette": "👤",
  "busts_in_silhouette": "👥",
  "butter": "🧈",
  "butterfly": "🦋",
  "cactus": "🌵",
  "cake": "🍰",
  "calendar": "📆",
  "call_me_hand": "🤙",
  "calling": "📲",
  "cambodia": "🇰🇭",
  "camel": "🐫",
  "camera": "📷",
  "camera_flash": "📸",
  "cameroon": "🇨🇲",
  "camping": "🏕",
  "canada": "🇨🇦",
  "canary_islands": "🇮🇨",
  "cancer": "♋",
  "candle": "🕯",
  "candy": "🍬",
  "canned_food": "🥫",
  "canoe": "🛶",
  "cape_verde": "🇨🇻",
  "capital_abcd": "🔠",
  "capricorn": "♑",
  "car": "🚗",
  "card_file_box": "🗃",
  "card_index": "📇",
  "card_index_dividers": "🗂",
  "caribbean_netherlands": "🇧🇶",
  "carousel_horse": "🎠",
  "carpentry_saw": "🪚",
  "carrot": "🥕",
  "cartwheeling": "🤸",
  "cat": "🐱",
  "cat2": "🐈",
  "cayman_islands": "🇰🇾",
  "cd": "💿",
  "central_african_republic": "🇨🇫",
  "ceuta_melilla": "🇪🇦",
  "chad": "🇹🇩",
  "chains": "⛓",
  "chair": "🪑",
  "champagne": "🍾",
  "chart": "💹",
  "chart_with_downwards_trend": "📉",
  "chart_with_upwards_trend": "📈",
  "cheese": "🧀",
  "cherries": "🍒",
  "cherry_blossom": "🌸",
  "chess_pawn": "♟",
  "chestnut": "🌰",
  "chicken": "🐔",
  "child": "🧒",
  "children_crossing": "🚸",
  "chile": "🇨🇱",
  "chipmunk": "🐿",
  "chocolate_bar": "🍫",
  "chopsticks": "🥢",
  "christmas_island": "🇨🇽",
  "christmas_tree": "🎄",
  "church": "⛪",
  "cinema": "🎦",
  "circus_tent": "🎪",
  "city_sunrise": "🌇",
  "city_sunset": "🌆",
  "cityscape": "🏙",
  "cl": "🆑",
  "clamp": "🗜",
  "clapper": "🎬",
  "classical_building": "🏛",
  "climbing": "🧗",
  "climbing_man": "🧗♂",
  "climbing_woman": "🧗♀",
  "clinking_glasses": "🥂",
  "clipboard": "📋",
  "clipperton_island": "🇨🇵",
  "clock1": "🕐",
  "clock10": "🕙",
  "clock1030": "🕥",
  "clock11": "🕚",
  "clock1130": "🕦",
  "clock12": "🕛",
  "clock1230": "🕧",
  "clock130": "🕜",
  "clock2": "🕑",
  "clock230": "🕝",
  "clock3": "🕒",
  "clock330": "🕞",
  "clock4": "🕓",
  "clock430": "🕟",
  "clock5": "🕔",
  "clock530": "🕠",
  "clock6": "🕕",
  "clock630": "🕡",
  "clock7": "🕖",
  "clock730": "🕢",
  "clock8": "🕗",
  "clock830": "🕣",
  "clock9": "🕘",
  "clock930": "🕤",
  "closed_book": "📕",
  "closed_lock_with_key": "🔐",
  "closed_umbrella": "🌂",
  "cloud": "☁",
  "cloud_with_lightning": "🌩",
  "cloud_with_lightning_and_rain": "⛈",
  "cloud_with_rain": "🌧",
  "cloud_with_snow": "🌨",
  "clown_face": "🤡",
  "clubs": "♣",
  "cn": "🇨🇳",
  "coat": "🧥",
  "cockroach": "🪳",
  "cocktail": "🍸",
  "coconut": "🥥",
  "cocos_islands": "🇨🇨",
  "coffee": "☕",
  "coffin": "⚰",
  "coin": "🪙",
  "cold_face": "🥶",
  "cold_sweat": "😰",
  "collision": "💥",
  "colombia": "🇨🇴",
  "comet": "☄",
  "comoros": "🇰🇲",
  "compass": "🧭",
  "computer_mouse": "🖱",
  "confetti_ball": "🎊",
  "confounded": "😖",
  "confused": "😕",
  "congo_brazzaville": "🇨🇬",
  "congo_kinshasa": "🇨🇩",
  "congratulations": "㊗",
  "construction": "🚧",
  "construction_worker": "👷",
  "construction_worker_man": "👷♂",
  "construction_worker_woman": "👷♀",
  "control_knobs": "🎛",
  "convenience_store": "🏪",
  "cook": "🧑🍳",
  "cook_islands": "🇨🇰",
  "cookie": "🍪",
  "cool": "🆒",
  "cop": "👮",
  "copyright": "©",
  "coral": "🪸",
  "corn": "🌽",
  "costa_rica": "🇨🇷",
  "cote_divoire": "🇨🇮",
  "couch_and_lamp": "🛋",
  "couple": "👫",
  "couple_with_heart": "💑",
  "couple_with_heart_man_man": "👨❤👨",
  "couple_with_heart_woman_man": "👩❤👨",
  "couple_with_heart_woman_woman": "👩❤👩",
  "couplekiss": "💏",
  "couplekiss_man_man": "👨❤💋👨",
  "couplekiss_man_woman": "👩❤💋👨",
  "couplekiss_woman_woman": "👩❤💋👩",
  "cow": "🐮",
  "cow2": "🐄",
  "cowboy_hat_face": "🤠",
  "crab": "🦀",
  "crayon": "🖍",
  "credit_card": "💳",
  "crescent_moon": "🌙",
  "cricket": "🦗",
  "cricket_game": "🏏",
  "croatia": "🇭🇷",
  "crocodile": "🐊",
  "croissant": "🥐",
  "crossed_fingers": "🤞",
  "crossed_flags": "🎌",
  "crossed_swords": "⚔",
  "crown": "👑",
  "crutch": "🩼",
  "cry": "😢",
  "crying_cat_face": "😿",
  "crystal_ball": "🔮",
  "cuba": "🇨🇺",
  "cucumber": "🥒",
  "cup_with_straw": "🥤",
  "cupcake": "🧁",
  "cupid": "💘",
  "curacao": "🇨🇼",
  "curling_stone": "🥌",
  "curly_haired_man": "👨🦱",
  "curly_haired_woman": "👩🦱",
  "curly_loop": "➰",
  "currency_exchange": "💱",
  "curry": "🍛",
  "cursing_face": "🤬",
  "custard": "🍮",
  "customs": "🛃",
  "cut_of_meat": "🥩",
  "cyclone": "🌀",
  "cyprus": "🇨🇾",
  "czech_republic": "🇨🇿",
  "dagger": "🗡",
  "dancer": "💃",
  "dancers": "👯",
  "dancing_men": "👯♂",
  "dancing_women": "👯♀",
  "dango": "🍡",
  "dark_sunglasses": "🕶",
  "dart": "🎯",
  "dash": "💨",
  "date": "📅",
  "de": "🇩🇪",
  "deaf_man": "🧏♂",
  "deaf_person": "🧏",
  "deaf_woman": "🧏♀",
  "deciduous_tree": "🌳",
  "deer": "🦌",
  "denmark": "🇩🇰",
  "department_store": "🏬",
  "derelict_house": "🏚",
  "desert": "🏜",
  "desert_island": "🏝",
  "desktop_computer": "🖥",
  "detective": "🕵",
  "diamond_shape_with_a_dot_inside": "💠",
  "diamonds": "♦",
  "diego_garcia": "🇩🇬",
  "disappointed": "😞",
  "disappointed_relieved": "😥",
  "disguised_face": "🥸",
  "diving_mask": "🤿",
  "diya_lamp": "🪔",
  "dizzy": "💫",
  "dizzy_face": "😵",
  "djibouti": "🇩🇯",
  "dna": "🧬",
  "do_not_litter": "🚯",
  "dodo": "🦤",
  "dog": "🐶",
  "dog2": "🐕",
  "dollar": "💵",
  "dolls": "🎎",
  "dolphin": "🐬",
  "dominica": "🇩🇲",
  "dominican_republic": "🇩🇴",
  "donkey": "🫏",
  "door": "🚪",
  "dotted_line_face": "🫥",
  "doughnut": "🍩",
  "dove": "🕊",
  "dragon": "🐉",
  "dragon_face": "🐲",
  "dress": "👗",
  "dromedary_camel": "🐪",
  "drooling_face": "🤤",
  "drop_of_blood": "🩸",
  "droplet": "💧",
  "drum": "🥁",
  "duck": "🦆",
  "dumpling": "🥟",
  "dvd": "📀",
  "e-mail": "📧",
  "eagle": "🦅",
  "ear": "👂",
  "ear_of_rice": "🌾",
  "ear_with_hearing_aid": "🦻",
  "earth_africa": "🌍",
  "earth_americas": "🌎",
  "earth_asia": "🌏",
  "ecuador": "🇪🇨",
  "egg": "🥚",
  "eggplant": "🍆",
  "egypt": "🇪🇬",
  "eight": "8⃣",
  "eight_pointed_black_star": "✴",
  "eight_spoked_asterisk": "✳",
  "eject_button": "⏏",
  "el_salvador": "🇸🇻",
  "electric_plug": "🔌",
  "elephant": "🐘",
  "elevator": "🛗",
  "elf": "🧝",
  "elf_man": "🧝♂",
  "elf_woman": "🧝♀",
  "email": "📧",
  "empty_nest": "🪹",
  "end": "🔚",
  "england": "🏴󠁧󠁢󠁥󠁮󠁧󠁿",
  "envelope": "✉",
  "envelope_with_arrow": "📩",
  "equatorial_guinea": "🇬🇶",
  "eritrea": "🇪🇷",
  "es": "🇪🇸",
  "estonia": "🇪🇪",
  "ethiopia": "🇪🇹",
  "eu": "🇪🇺",
  "euro": "💶",
  "european_castle": "🏰",
  "european_post_office": "🏤",
  "european_union": "🇪🇺",
  "evergreen_tree": "🌲",
  "exclamation": "❗",
  "expressionless": "😑",
  "eye": "👁",
  "eye_speech_bubble": "👁🗨",
  "eyeglasses": "👓",
  "face_exhaling": "😮💨",
  "face_holding_back_tears": "🥹",
  "face_in_clouds": "😶🌫",
  "face_with_diagonal_mouth": "🫤",
  "face_with_head_bandage": "🤕",
  "face_with_open_eyes_and_hand_over_mouth": "🫢",
  "face_with_peeking_eye": "🫣",
  "face_with_spiral_eyes": "😵💫",
  "face_with_thermometer": "🤒",
  "facepunch": "👊",
  "factory": "🏭",
  "factory_worker": "🧑🏭",
  "fairy": "🧚",
  "fairy_man": "🧚♂",
  "fairy_woman": "🧚♀",
  "falafel": "🧆",
  "falkland_islands": "🇫🇰",
  "fallen_leaf": "🍂",
  "family": "👪",
  "family_man_boy": "👨👦",
  "family_man_boy_boy": "👨👦👦",
  "family_man_girl": "👨👧",
  "family_man_girl_boy": "👨👧👦",
  "family_man_girl_girl": "👨👧👧",
  "family_man_man_boy": "👨👨👦",
  "family_man_man_boy_boy": "👨👨👦👦",
  "family_man_man_girl": "👨👨👧",
  "family_man_man_girl_boy": "👨👨👧👦",
  "family_man_man_girl_girl": "👨👨👧👧",
  "family_man_woman_boy": "👨👩👦",
  "family_man_woman_boy_boy": "👨👩👦👦",
  "family_man_woman_girl": "👨👩👧",
  "family_man_woman_girl_boy": "👨👩👧👦",
  "family_man_woman_girl_girl": "👨👩👧👧",
  "family_woman_boy": "👩👦",
  "family_woman_boy_boy": "👩👦👦",
  "family_woman_girl": "👩👧",
  "family_woman_girl_boy": "👩👧👦",
  "family_woman_girl_girl": "👩👧👧",
  "family_woman_woman_boy": "👩👩👦",
  "family_woman_woman_boy_boy": "👩👩👦👦",
  "family_woman_woman_girl": "👩👩👧",
  "family_woman_woman_girl_boy": "👩👩👧👦",
  "family_woman_woman_girl_girl": "👩👩👧👧",
  "farmer": "🧑🌾",
  "faroe_islands": "🇫🇴",
  "fast_forward": "⏩",
  "fax": "📠",
  "fearful": "😨",
  "feather": "🪶",
  "feet": "🐾",
  "female_detective": "🕵♀",
  "female_sign": "♀",
  "ferris_wheel": "🎡",
  "ferry": "⛴",
  "field_hockey": "🏑",
  "fiji": "🇫🇯",
  "file_cabinet": "🗄",
  "file_folder": "📁",
  "film_projector": "📽",
  "film_strip": "🎞",
  "finland": "🇫🇮",
  "fire_engine": "🚒",
  "fire_extinguisher": "🧯",
  "firecracker": "🧨",
  "firefighter": "🧑🚒",
  "fireworks": "🎆",
  "first_quarter_moon": "🌓",
  "first_quarter_moon_with_face": "🌛",
  "fish": "🐟",
  "fish_cake": "🍥",
  "fishing_pole_and_fish": "🎣",
  "fist": "✊",
  "fist_left": "🤛",
  "fist_oncoming": "👊",
  "fist_raised": "✊",
  "fist_right": "🤜",
  "five": "5⃣",
  "flags": "🎏",
  "flamingo": "🦩",
  "flashlight": "🔦",
  "flat_shoe": "🥿",
  "flatbread": "🫓",
  "fleur_de_lis": "⚜",
  "flight_arrival": "🛬",
  "flight_departure": "🛫",
  "flipper": "🐬",
  "floppy_disk": "💾",
  "flower_playing_cards": "🎴",
  "flushed": "😳",
  "flute": "🪈",
  "fly": "🪰",
  "flying_disc": "🥏",
  "flying_saucer": "🛸",
  "fog": "🌫",
  "foggy": "🌁",
  "folding_hand_fan": "🪭",
  "fondue": "🫕",
  "foot": "🦶",
  "football": "🏈",
  "footprints": "👣",
  "fork_and_knife": "🍴",
  "fortune_cookie": "🥠",
  "fountain": "⛲",
  "fountain_pen": "🖋",
  "four": "4⃣",
  "four_leaf_clover": "🍀",
  "fox_face": "🦊",
  "fr": "🇫🇷",
  "framed_picture": "🖼",
  "free": "🆓",
  "french_guiana": "🇬🇫",
  "french_polynesia": "🇵🇫",
  "french_southern_territories": "🇹🇫",
  "fried_egg": "🍳",
  "fried_shrimp": "🍤",
  "fries": "🍟",
  "frog": "🐸",
  "frowning": "😦",
  "frowning_face": "☹",
  "frowning_man": "🙍♂",
  "frowning_person": "🙍",
  "frowning_woman": "🙍♀",
  "fu": "🖕",
  "fuelpump": "⛽",
  "full_moon": "🌕",
  "full_moon_with_face": "🌝",
  "funeral_urn": "⚱",
  "gabon": "🇬🇦",
  "gambia": "🇬🇲",
  "game_die": "🎲",
  "garlic": "🧄",
  "gb": "🇬🇧",
  "gem": "💎",
  "gemini": "♊",
  "genie": "🧞",
  "genie_man": "🧞♂",
  "genie_woman": "🧞♀",
  "georgia": "🇬🇪",
  "ghana": "🇬🇭",
  "ghost": "👻",
  "gibraltar": "🇬🇮",
  "gift": "🎁",
  "gift_heart": "💝",
  "ginger_root": "🫚",
  "giraffe": "🦒",
  "girl": "👧",
  "globe_with_meridians": "🌐",
  "gloves": "🧤",
  "goal_net": "🥅",
  "goat": "🐐",
  "goggles": "🥽",
  "golf": "⛳",
  "golfing": "🏌",
  "golfing_man": "🏌♂",
  "golfing_woman": "🏌♀",
  "goose": "🪿",
  "gorilla": "🦍",
  "grapes": "🍇",
  "greece": "🇬🇷",
  "green_apple": "🍏",
  "green_book": "📗",
  "green_circle": "🟢",
  "green_heart": "💚",
  "green_salad": "🥗",
  "green_square": "🟩",
  "greenland": "🇬🇱",
  "grenada": "🇬🇩",
  "grey_exclamation": "❕",
  "grey_heart": "🩶",
  "grey_question": "❔",
  "grimacing": "😬",
  "grinning": "😀",
  "guadeloupe": "🇬🇵",
  "guam": "🇬🇺",
  "guard": "💂",
  "guardsman": "💂♂",
  "guardswoman": "💂♀",
  "guatemala": "🇬🇹",
  "guernsey": "🇬🇬",
  "guide_dog": "🦮",
  "guinea": "🇬🇳",
  "guinea_bissau": "🇬🇼",
  "guitar": "🎸",
  "gun": "🔫",
  "guyana": "🇬🇾",
  "hair_pick": "🪮",
  "haircut": "💇",
  "haircut_man": "💇♂",
  "haircut_woman": "💇♀",
  "haiti": "🇭🇹",
  "hamburger": "🍔",
  "hammer": "🔨",
  "hammer_and_pick": "⚒",
  "hammer_and_wrench": "🛠",
  "hamsa": "🪬",
  "hamster": "🐹",
  "hand": "✋",
  "hand_over_mouth": "🤭",
  "hand_with_index_finger_and_thumb_crossed": "🫰",
  "handbag": "👜",
  "handball_person": "🤾",
  "handshake": "🤝",
  "hankey": "💩",
  "hash": "#⃣",
  "hatched_chick": "🐥",
  "hatching_chick": "🐣",
  "headphones": "🎧",
  "headstone": "🪦",
  "health_worker": "🧑⚕",
  "hear_no_evil": "🙉",
  "heard_mcdonald_islands": "🇭🇲",
  "heart_decoration": "💟",
  "heart_eyes": "😍",
  "heart_eyes_cat": "😻",
  "heart_hands": "🫶",
  "heart_on_fire": "❤🔥",
  "heartbeat": "💓",
  "heartpulse": "💗",
  "hearts": "♥",
  "heavy_division_sign": "➗",
  "heavy_dollar_sign": "💲",
  "heavy_equals_sign": "🟰",
  "heavy_exclamation_mark": "❗",
  "heavy_heart_exclamation": "❣",
  "heavy_minus_sign": "➖",
  "heavy_multiplication_x": "✖",
  "heavy_plus_sign": "➕",
  "hedgehog": "🦔",
  "helicopter": "🚁",
  "herb": "🌿",
  "hibiscus": "🌺",
  "high_brightness": "🔆",
  "high_heel": "👠",
  "hiking_boot": "🥾",
  "hindu_temple": "🛕",
  "hippopotamus": "🦛",
  "hocho": "🔪",
  "hole": "🕳",
  "honduras": "🇭🇳",
  "honey_pot": "🍯",
  "honeybee": "🐝",
  "hong_kong": "🇭🇰",
  "hook": "🪝",
  "horse": "🐴",
  "horse_racing": "🏇",
  "hospital": "🏥",
  "hot_face": "🥵",
  "hot_pepper": "🌶",
  "hotdog": "🌭",
  "hotel": "🏨",
  "hotsprings": "♨",
  "hourglass": "⌛",
  "hourglass_flowing_sand": "⏳",
  "house": "🏠",
  "house_with_garden": "🏡",
  "houses": "🏘",
  "hugs": "🤗",
  "hungary": "🇭🇺",
  "hushed": "😯",
  "hut": "🛖",
  "hyacinth": "🪻",
  "ice_cream": "🍨",
  "ice_cube": "🧊",
  "ice_hockey": "🏒",
  "ice_skate": "⛸",
  "icecream": "🍦",
  "iceland": "🇮🇸",
  "id": "🆔",
  "identification_card": "🪪",
  "ideograph_advantage": "🉐",
  "imp": "👿",
  "inbox_tray": "📥",
  "incoming_envelope": "📨",
  "index_pointing_at_the_viewer": "🫵",
  "india": "🇮🇳",
  "indonesia": "🇮🇩",
  "infinity": "♾",
  "information_desk_person": "💁",
  "information_source": "ℹ",
  "innocent": "😇",
  "interrobang": "⁉",
  "iphone": "📱",
  "iran": "🇮🇷",
  "iraq": "🇮🇶",
  "ireland": "🇮🇪",
  "isle_of_man": "🇮🇲",
  "israel": "🇮🇱",
  "it": "🇮🇹",
  "izakaya_lantern": "🏮",
  "jack_o_lantern": "🎃",
  "jamaica": "🇯🇲",
  "japan": "🗾",
  "japanese_castle": "🏯",
  "japanese_goblin": "👺",
  "japanese_ogre": "👹",
  "jar": "🫙",
  "jeans": "👖",
  "jellyfish": "🪼",
  "jersey": "🇯🇪",
  "jigsaw": "🧩",
  "jordan": "🇯🇴",
  "joy_cat": "😹",
  "joystick": "🕹",
  "jp": "🇯🇵",
  "judge": "🧑⚖",
  "juggling_person": "🤹",
  "kaaba": "🕋",
  "kangaroo": "🦘",
  "kazakhstan": "🇰🇿",
  "kenya": "🇰🇪",
  "keyboard": "⌨",
  "keycap_ten": "🔟",
  "khanda": "🪯",
  "kick_scooter": "🛴",
  "kimono": "👘",
  "kiribati": "🇰🇮",
  "kiss": "💋",
  "kissing": "😗",
  "kissing_cat": "😽",
  "kissing_closed_eyes": "😚",
  "kissing_heart": "😘",
  "kissing_smiling_eyes": "😙",
  "kite": "🪁",
  "kiwi_fruit": "🥝",
  "kneeling_man": "🧎♂",
  "kneeling_person": "🧎",
  "kneeling_woman": "🧎♀",
  "knife": "🔪",
  "knot": "🪢",
  "koala": "🐨",
  "koko": "🈁",
  "kosovo": "🇽🇰",
  "kr": "🇰🇷",
  "kuwait": "🇰🇼",
  "kyrgyzstan": "🇰🇬",
  "lab_coat": "🥼",
  "label": "🏷",
  "lacrosse": "🥍",
  "ladder": "🪜",
  "lady_beetle": "🐞",
  "lantern": "🏮",
  "laos": "🇱🇦",
  "large_blue_circle": "🔵",
  "large_blue_diamond": "🔷",
  "large_orange_diamond": "🔶",
  "last_quarter_moon": "🌗",
  "last_quarter_moon_with_face": "🌜",
  "latin_cross": "✝",
  "latvia": "🇱🇻",
  "laughing": "😆",
  "leafy_green": "🥬",
  "leaves": "🍃",
  "lebanon": "🇱🇧",
  "ledger": "📒",
  "left_luggage": "🛅",
  "left_right_arrow": "↔",
  "left_speech_bubble": "🗨",
  "leftwards_arrow_with_hook": "↩",
  "leftwards_hand": "🫲",
  "leftwards_pushing_hand": "🫷",
  "leg": "🦵",
  "lemon": "🍋",
  "leo": "♌",
  "leopard": "🐆",
  "lesotho": "🇱🇸",
  "level_slider": "🎚",
  "liberia": "🇱🇷",
  "libra": "♎",
  "libya": "🇱🇾",
  "liechtenstein": "🇱🇮",
  "light_blue_heart": "🩵",
  "light_rail": "🚈",
  "link": "🔗",
  "lion": "🦁",
  "lips": "👄",
  "lipstick": "💄",
  "lithuania": "🇱🇹",
  "lizard": "🦎",
  "llama": "🦙",
  "lobster": "🦞",
  "lock_with_ink_pen": "🔏",
  "lollipop": "🍭",
  "long_drum": "🪘",
  "loop": "➿",
  "lotion_bottle": "🧴",
  "lotus": "🪷",
  "lotus_position": "🧘",
  "lotus_position_man": "🧘♂",
  "lotus_position_woman": "🧘♀",
  "loud_sound": "🔊",
  "loudspeaker": "📢",
  "love_hotel": "🏩",
  "love_letter": "💌",
  "love_you_gesture": "🤟",
  "low_battery": "🪫",
  "low_brightness": "🔅",
  "luggage": "🧳",
  "lungs": "🫁",
  "luxembourg": "🇱🇺",
  "lying_face": "🤥",
  "m": "Ⓜ",
  "macau": "🇲🇴",
  "macedonia": "🇲🇰",
  "madagascar": "🇲🇬",
  "mag": "🔍",
  "mag_right": "🔎",
  "mage": "🧙",
  "mage_man": "🧙♂",
  "mage_woman": "🧙♀",
  "magic_wand": "🪄",
  "magnet": "🧲",
  "mahjong": "🀄",
  "mailbox": "📫",
  "mailbox_closed": "📪",
  "mailbox_with_mail": "📬",
  "mailbox_with_no_mail": "📭",
  "malawi": "🇲🇼",
  "malaysia": "🇲🇾",
  "maldives": "🇲🇻",
  "male_detective": "🕵♂",
  "male_sign": "♂",
  "mali": "🇲🇱",
  "malta": "🇲🇹",
  "mammoth": "🦣",
  "man": "👨",
  "man_artist": "👨🎨",
  "man_astronaut": "👨🚀",
  "man_beard": "🧔♂",
  "man_cartwheeling": "🤸♂",
  "man_cook": "👨🍳",
  "man_dancing": "🕺",
  "man_facepalming": "🤦♂",
  "man_factory_worker": "👨🏭",
  "man_farmer": "👨🌾",
  "man_feeding_baby": "👨🍼",
  "man_firefighter": "👨🚒",
  "man_health_worker": "👨⚕",
  "man_in_manual_wheelchair": "👨🦽",
  "man_in_motorized_wheelchair": "👨🦼",
  "man_in_tuxedo": "🤵♂",
  "man_judge": "👨⚖",
  "man_juggling": "🤹♂",
  "man_mechanic": "👨🔧",
  "man_office_worker": "👨💼",
  "man_pilot": "👨✈",
  "man_playing_handball": "🤾♂",
  "man_playing_water_polo": "🤽♂",
  "man_scientist": "👨🔬",
  "man_shrugging": "🤷♂",
  "man_singer": "👨🎤",
  "man_student": "👨🎓",
  "man_teacher": "👨🏫",
  "man_technologist": "👨💻",
  "man_with_gua_pi_mao": "👲",
  "man_with_probing_cane": "👨🦯",
  "man_with_turban": "👳♂",
  "man_with_veil": "👰♂",
  "mandarin": "🍊",
  "mango": "🥭",
  "mans_shoe": "👞",
  "mantelpiece_clock": "🕰",
  "manual_wheelchair": "🦽",
  "maple_leaf": "🍁",
  "maracas": "🪇",
  "marshall_islands": "🇲🇭",
  "martial_arts_uniform": "🥋",
  "martinique": "🇲🇶",
  "mask": "😷",
  "massage": "💆",
  "massage_man": "💆♂",
  "massage_woman": "💆♀",
  "mate": "🧉",
  "mauritania": "🇲🇷",
  "mauritius": "🇲🇺",
  "mayotte": "🇾🇹",
  "meat_on_bone": "🍖",
  "mechanic": "🧑🔧",
  "mechanical_arm": "🦾",
  "mechanical_leg": "🦿",
  "medal_military": "🎖",
  "medal_sports": "🏅",
  "medical_symbol": "⚕",
  "mega": "📣",
  "melon": "🍈",
  "melting_face": "🫠",
  "men_wrestling": "🤼♂",
  "mending_heart": "❤🩹",
  "menorah": "🕎",
  "mens": "🚹",
  "mermaid": "🧜♀",
  "merman": "🧜♂",
  "merperson": "🧜",
  "metal": "🤘",
  "metro": "🚇",
  "mexico": "🇲🇽",
  "microbe": "🦠",
  "micronesia": "🇫🇲",
  "microphone": "🎤",
  "microscope": "🔬",
  "middle_finger": "🖕",
  "military_helmet": "🪖",
  "milk_glass": "🥛",
  "milky_way": "🌌",
  "minibus": "🚐",
  "minidisc": "💽",
  "mirror": "🪞",
  "mirror_ball": "🪩",
  "mobile_phone_off": "📴",
  "moldova": "🇲🇩",
  "monaco": "🇲🇨",
  "money_mouth_face": "🤑",
  "money_with_wings": "💸",
  "moneybag": "💰",
  "mongolia": "🇲🇳",
  "monkey": "🐒",
  "monkey_face": "🐵",
  "monocle_face": "🧐",
  "monorail": "🚝",
  "montenegro": "🇲🇪",
  "montserrat": "🇲🇸",
  "moon": "🌔",
  "moon_cake": "🥮",
  "moose": "🫎",
  "morocco": "🇲🇦",
  "mortar_board": "🎓",
  "mosque": "🕌",
  "mosquito": "🦟",
  "motor_boat": "🛥",
  "motor_scooter": "🛵",
  "motorcycle": "🏍",
  "motorized_wheelchair": "🦼",
  "motorway": "🛣",
  "mount_fuji": "🗻",
  "mountain": "⛰",
  "mountain_bicyclist": "🚵",
  "mountain_biking_man": "🚵♂",
  "mountain_biking_woman": "🚵♀",
  "mountain_cableway": "🚠",
  "mountain_railway": "🚞",
  "mountain_snow": "🏔",
  "mouse": "🐭",
  "mouse_trap": "🪤",
  "mouse2": "🐁",
  "movie_camera": "🎥",
  "moyai": "🗿",
  "mozambique": "🇲🇿",
  "mrs_claus": "🤶",
  "mushroom": "🍄",
  "musical_keyboard": "🎹",
  "musical_note": "🎵",
  "musical_score": "🎼",
  "mute": "🔇",
  "mx_claus": "🧑🎄",
  "myanmar": "🇲🇲",
  "nail_care": "💅",
  "name_badge": "📛",
  "namibia": "🇳🇦",
  "national_park": "🏞",
  "nauru": "🇳🇷",
  "nauseated_face": "🤢",
  "nazar_amulet": "🧿",
  "necktie": "👔",
  "negative_squared_cross_mark": "❎",
  "nepal": "🇳🇵",
  "nest_with_eggs": "🪺",
  "nesting_dolls": "🪆",
  "netherlands": "🇳🇱",
  "neutral_face": "😐",
  "new": "🆕",
  "new_caledonia": "🇳🇨",
  "new_moon": "🌑",
  "new_moon_with_face": "🌚",
  "new_zealand": "🇳🇿",
  "newspaper": "📰",
  "newspaper_roll": "🗞",
  "next_track_button": "⏭",
  "ng": "🆖",
  "ng_man": "🙅♂",
  "ng_woman": "🙅♀",
  "nicaragua": "🇳🇮",
  "niger": "🇳🇪",
  "nigeria": "🇳🇬",
  "night_with_stars": "🌃",
  "nine": "9⃣",
  "ninja": "🥷",
  "niue": "🇳🇺",
  "no_bell": "🔕",
  "no_bicycles": "🚳",
  "no_entry": "⛔",
  "no_entry_sign": "🚫",
  "no_good": "🙅",
  "no_good_man": "🙅♂",
  "no_good_woman": "🙅♀",
  "no_mobile_phones": "📵",
  "no_mouth": "😶",
  "no_pedestrians": "🚷",
  "no_smoking": "🚭",
  "non-potable_water": "🚱",
  "norfolk_island": "🇳🇫",
  "north_korea": "🇰🇵",
  "northern_mariana_islands": "🇲🇵",
  "norway": "🇳🇴",
  "nose": "👃",
  "notebook": "📓",
  "notebook_with_decorative_cover": "📔",
  "notes": "🎶",
  "nut_and_bolt": "🔩",
  "o": "⭕",
  "o2": "🅾",
  "ocean": "🌊",
  "octopus": "🐙",
  "oden": "🍢",
  "office": "🏢",
  "office_worker": "🧑💼",
  "oil_drum": "🛢",
  "ok": "🆗",
  "ok_hand": "👌",
  "ok_man": "🙆♂",
  "ok_person": "🙆",
  "ok_woman": "🙆♀",
  "old_key": "🗝",
  "older_adult": "🧓",
  "older_man": "👴",
  "older_woman": "👵",
  "olive": "🫒",
  "om": "🕉",
  "oman": "🇴🇲",
  "on": "🔛",
  "oncoming_automobile": "🚘",
  "oncoming_bus": "🚍",
  "oncoming_police_car": "🚔",
  "oncoming_taxi": "🚖",
  "one": "1⃣",
  "one_piece_swimsuit": "🩱",
  "onion": "🧅",
  "open_book": "📖",
  "open_file_folder": "📂",
  "open_hands": "👐",
  "open_mouth": "😮",
  "open_umbrella": "☂",
  "ophiuchus": "⛎",
  "orange": "🍊",
  "orange_book": "📙",
  "orange_circle": "🟠",
  "orange_heart": "🧡",
  "orange_square": "🟧",
  "orangutan": "🦧",
  "orthodox_cross": "☦",
  "otter": "🦦",
  "outbox_tray": "📤",
  "owl": "🦉",
  "ox": "🐂",
  "oyster": "🦪",
  "page_facing_up": "📄",
  "page_with_curl": "📃",
  "pager": "📟",
  "paintbrush": "🖌",
  "pakistan": "🇵🇰",
  "palau": "🇵🇼",
  "palestinian_territories": "🇵🇸",
  "palm_down_hand": "🫳",
  "palm_tree": "🌴",
  "palm_up_hand": "🫴",
  "palms_up_together": "🤲",
  "panama": "🇵🇦",
  "pancakes": "🥞",
  "panda_face": "🐼",
  "paperclip": "📎",
  "paperclips": "🖇",
  "papua_new_guinea": "🇵🇬",
  "parachute": "🪂",
  "paraguay": "🇵🇾",
  "parasol_on_ground": "⛱",
  "parking": "🅿",
  "parrot": "🦜",
  "part_alternation_mark": "〽",
  "partly_sunny": "⛅",
  "partying_face": "🥳",
  "passenger_ship": "🛳",
  "passport_control": "🛂",
  "pause_button": "⏸",
  "paw_prints": "🐾",
  "pea_pod": "🫛",
  "peace_symbol": "☮",
  "peach": "🍑",
  "peacock": "🦚",
  "peanuts": "🥜",
  "pear": "🍐",
  "pen": "🖊",
  "pencil": "📝",
  "pencil2": "✏",
  "penguin": "🐧",
  "pensive": "😔",
  "people_holding_hands": "🧑🤝🧑",
  "people_hugging": "🫂",
  "performing_arts": "🎭",
  "persevere": "😣",
  "person_bald": "🧑🦲",
  "person_curly_hair": "🧑🦱",
  "person_feeding_baby": "🧑🍼",
  "person_fencing": "🤺",
  "person_in_manual_wheelchair": "🧑🦽",
  "person_in_motorized_wheelchair": "🧑🦼",
  "person_in_tuxedo": "🤵",
  "person_red_hair": "🧑🦰",
  "person_white_hair": "🧑🦳",
  "person_with_crown": "🫅",
  "person_with_probing_cane": "🧑🦯",
  "person_with_turban": "👳",
  "person_with_veil": "👰",
  "peru": "🇵🇪",
  "petri_dish": "🧫",
  "philippines": "🇵🇭",
  "phone": "☎",
  "pick": "⛏",
  "pickup_truck": "🛻",
  "pie": "🥧",
  "pig": "🐷",
  "pig_nose": "🐽",
  "pig2": "🐖",
  "pill": "💊",
  "pilot": "🧑✈",
  "pinata": "🪅",
  "pinched_fingers": "🤌",
  "pinching_hand": "🤏",
  "pineapple": "🍍",
  "ping_pong": "🏓",
  "pink_heart": "🩷",
  "pirate_flag": "🏴☠",
  "pisces": "♓",
  "pitcairn_islands": "🇵🇳",
  "pizza": "🍕",
  "placard": "🪧",
  "place_of_worship": "🛐",
  "plate_with_cutlery": "🍽",
  "play_or_pause_button": "⏯",
  "playground_slide": "🛝",
  "pleading_face": "🥺",
  "plunger": "🪠",
  "point_down": "👇",
  "point_left": "👈",
  "point_right": "👉",
  "point_up": "☝",
  "point_up_2": "👆",
  "poland": "🇵🇱",
  "polar_bear": "🐻❄",
  "police_car": "🚓",
  "police_officer": "👮",
  "policeman": "👮♂",
  "policewoman": "👮♀",
  "poodle": "🐩",
  "poop": "💩",
  "popcorn": "🍿",
  "portugal": "🇵🇹",
  "post_office": "🏣",
  "postal_horn": "📯",
  "postbox": "📮",
  "potable_water": "🚰",
  "potato": "🥔",
  "potted_plant": "🪴",
  "pouch": "👝",
  "poultry_leg": "🍗",
  "pound": "💷",
  "pouring_liquid": "🫗",
  "pout": "😡",
  "pouting_cat": "😾",
  "pouting_face": "🙎",
  "pouting_man": "🙎♂",
  "pouting_woman": "🙎♀",
  "prayer_beads": "📿",
  "pregnant_man": "🫃",
  "pregnant_person": "🫄",
  "pregnant_woman": "🤰",
  "pretzel": "🥨",
  "previous_track_button": "⏮",
  "prince": "🤴",
  "princess": "👸",
  "printer": "🖨",
  "probing_cane": "🦯",
  "puerto_rico": "🇵🇷",
  "punch": "👊",
  "purple_circle": "🟣",
  "purple_heart": "💜",
  "purple_square": "🟪",
  "purse": "👛",
  "pushpin": "📌",
  "put_litter_in_its_place": "🚮",
  "qatar": "🇶🇦",
  "question": "❓",
  "rabbit": "🐰",
  "rabbit2": "🐇",
  "raccoon": "🦝",
  "racehorse": "🐎",
  "racing_car": "🏎",
  "radio": "📻",
  "radio_button": "🔘",
  "radioactive": "☢",
  "rage": "😡",
  "railway_car": "🚃",
  "railway_track": "🛤",
  "rainbow": "🌈",
  "rainbow_flag": "🏳🌈",
  "raised_back_of_hand": "🤚",
  "raised_eyebrow": "🤨",
  "raised_hand": "✋",
  "raised_hand_with_fingers_splayed": "🖐",
  "raised_hands": "🙌",
  "raising_hand": "🙋",
  "raising_hand_man": "🙋♂",
  "raising_hand_woman": "🙋♀",
  "ram": "🐏",
  "ramen": "🍜",
  "rat": "🐀",
  "razor": "🪒",
  "receipt": "🧾",
  "record_button": "⏺",
  "recycle": "♻",
  "red_car": "🚗",
  "red_circle": "🔴",
  "red_envelope": "🧧",
  "red_haired_man": "👨🦰",
  "red_haired_woman": "👩🦰",
  "red_square": "🟥",
  "registered": "®",
  "relaxed": "☺",
  "relieved": "😌",
  "reminder_ribbon": "🎗",
  "repeat": "🔁",
  "repeat_one": "🔂",
  "rescue_worker_helmet": "⛑",
  "restroom": "🚻",
  "reunion": "🇷🇪",
  "revolving_hearts": "💞",
  "rewind": "⏪",
  "rhinoceros": "🦏",
  "ribbon": "🎀",
  "rice": "🍚",
  "rice_ball": "🍙",
  "rice_cracker": "🍘",
  "rice_scene": "🎑",
  "right_anger_bubble": "🗯",
  "rightwards_hand": "🫱",
  "rightwards_pushing_hand": "🫸",
  "ring": "💍",
  "ring_buoy": "🛟",
  "ringed_planet": "🪐",
  "rock": "🪨",
  "rofl": "🤣",
  "roll_eyes": "🙄",
  "roll_of_paper": "🧻",
  "roller_coaster": "🎢",
  "roller_skate": "🛼",
  "romania": "🇷🇴",
  "rooster": "🐓",
  "rose": "🌹",
  "rosette": "🏵",
  "rotating_light": "🚨",
  "round_pushpin": "📍",
  "rowboat": "🚣",
  "rowing_man": "🚣♂",
  "rowing_woman": "🚣♀",
  "ru": "🇷🇺",
  "rugby_football": "🏉",
  "runner": "🏃",
  "running": "🏃",
  "running_man": "🏃♂",
  "running_shirt_with_sash": "🎽",
  "running_woman": "🏃♀",
  "rwanda": "🇷🇼",
  "sa": "🈂",
  "safety_pin": "🧷",
  "safety_vest": "🦺",
  "sagittarius": "♐",
  "sailboat": "⛵",
  "sake": "🍶",
  "salt": "🧂",
  "saluting_face": "🫡",
  "samoa": "🇼🇸",
  "san_marino": "🇸🇲",
  "sandal": "👡",
  "sandwich": "🥪",
  "santa": "🎅",
  "sao_tome_principe": "🇸🇹",
  "sari": "🥻",
  "sassy_man": "💁♂",
  "sassy_woman": "💁♀",
  "satellite": "📡",
  "satisfied": "😆",
  "saudi_arabia": "🇸🇦",
  "sauna_man": "🧖♂",
  "sauna_person": "🧖",
  "sauna_woman": "🧖♀",
  "sauropod": "🦕",
  "saxophone": "🎷",
  "scarf": "🧣",
  "school": "🏫",
  "school_satchel": "🎒",
  "scientist": "🧑🔬",
  "scissors": "✂",
  "scorpion": "🦂",
  "scorpius": "♏",
  "scotland": "🏴󠁧󠁢󠁳󠁣󠁴󠁿",
  "scream": "😱",
  "scream_cat": "🙀",
  "screwdriver": "🪛",
  "scroll": "📜",
  "seal": "🦭",
  "seat": "💺",
  "secret": "㊙",
  "see_no_evil": "🙈",
  "seedling": "🌱",
  "selfie": "🤳",
  "senegal": "🇸🇳",
  "serbia": "🇷🇸",
  "service_dog": "🐕🦺",
  "seven": "7⃣",
  "sewing_needle": "🪡",
  "seychelles": "🇸🇨",
  "shaking_face": "🫨",
  "shallow_pan_of_food": "🥘",
  "shamrock": "☘",
  "shark": "🦈",
  "shaved_ice": "🍧",
  "sheep": "🐑",
  "shell": "🐚",
  "shinto_shrine": "⛩",
  "ship": "🚢",
  "shirt": "👕",
  "shit": "💩",
  "shoe": "👞",
  "shopping": "🛍",
  "shopping_cart": "🛒",
  "shorts": "🩳",
  "shower": "🚿",
  "shrimp": "🦐",
  "shushing_face": "🤫",
  "sierra_leone": "🇸🇱",
  "signal_strength": "📶",
  "singapore": "🇸🇬",
  "singer": "🧑🎤",
  "sint_maarten": "🇸🇽",
  "six": "6⃣",
  "six_pointed_star": "🔯",
  "skateboard": "🛹",
  "ski": "🎿",
  "skier": "⛷",
  "skull": "💀",
  "skull_and_crossbones": "☠",
  "skunk": "🦨",
  "sled": "🛷",
  "sleeping": "😴",
  "sleeping_bed": "🛌",
  "sleepy": "😪",
  "slightly_frowning_face": "🙁",
  "slightly_smiling_face": "🙂",
  "slot_machine": "🎰",
  "sloth": "🦥",
  "slovakia": "🇸🇰",
  "slovenia": "🇸🇮",
  "small_airplane": "🛩",
  "small_blue_diamond": "🔹",
  "small_orange_diamond": "🔸",
  "small_red_triangle": "🔺",
  "small_red_triangle_down": "🔻",
  "smile_cat": "😸",
  "smiley": "😃",
  "smiley_cat": "😺",
  "smiling_face_with_tear": "🥲",
  "smiling_face_with_three_hearts": "🥰",
  "smiling_imp": "😈",
  "smirk": "😏",
  "smirk_cat": "😼",
  "smoking": "🚬",
  "snail": "🐌",
  "snake": "🐍",
  "sneezing_face": "🤧",
  "snowboarder": "🏂",
  "snowflake": "❄",
  "snowman": "⛄",
  "snowman_with_snow": "☃",
  "soap": "🧼",
  "sob": "😭",
  "soccer": "⚽",
  "socks": "🧦",
  "softball": "🥎",
  "solomon_islands": "🇸🇧",
  "somalia": "🇸🇴",
  "soon": "🔜",
  "sos": "🆘",
  "sound": "🔉",
  "south_africa": "🇿🇦",
  "south_georgia_south_sandwich_islands": "🇬🇸",
  "south_sudan": "🇸🇸",
  "space_invader": "👾",
  "spades": "♠",
  "spaghetti": "🍝",
  "sparkle": "❇",
  "sparkler": "🎇",
  "sparkling_heart": "💖",
  "speak_no_evil": "🙊",
  "speaker": "🔈",
  "speaking_head": "🗣",
  "speedboat": "🚤",
  "spider": "🕷",
  "spider_web": "🕸",
  "spiral_calendar": "🗓",
  "spiral_notepad": "🗒",
  "sponge": "🧽",
  "spoon": "🥄",
  "squid": "🦑",
  "sri_lanka": "🇱🇰",
  "st_barthelemy": "🇧🇱",
  "st_helena": "🇸🇭",
  "st_kitts_nevis": "🇰🇳",
  "st_lucia": "🇱🇨",
  "st_martin": "🇲🇫",
  "st_pierre_miquelon": "🇵🇲",
  "st_vincent_grenadines": "🇻🇨",
  "stadium": "🏟",
  "standing_man": "🧍♂",
  "standing_person": "🧍",
  "standing_woman": "🧍♀",
  "star": "⭐",
  "star_and_crescent": "☪",
  "star_of_david": "✡",
  "star_struck": "🤩",
  "star2": "🌟",
  "stars": "🌠",
  "station": "🚉",
  "statue_of_liberty": "🗽",
  "steam_locomotive": "🚂",
  "stethoscope": "🩺",
  "stew": "🍲",
  "stop_button": "⏹",
  "stop_sign": "🛑",
  "stopwatch": "⏱",
  "straight_ruler": "📏",
  "strawberry": "🍓",
  "stuck_out_tongue": "😛",
  "stuck_out_tongue_closed_eyes": "😝",
  "stuck_out_tongue_winking_eye": "😜",
  "student": "🧑🎓",
  "studio_microphone": "🎙",
  "stuffed_flatbread": "🥙",
  "sudan": "🇸🇩",
  "sun_behind_large_cloud": "🌥",
  "sun_behind_rain_cloud": "🌦",
  "sun_behind_small_cloud": "🌤",
  "sun_with_face": "🌞",
  "sunflower": "🌻",
  "sunny": "☀",
  "sunrise": "🌅",
  "sunrise_over_mountains": "🌄",
  "superhero": "🦸",
  "superhero_man": "🦸♂",
  "superhero_woman": "🦸♀",
  "supervillain": "🦹",
  "supervillain_man": "🦹♂",
  "supervillain_woman": "🦹♀",
  "surfer": "🏄",
  "surfing_man": "🏄♂",
  "surfing_woman": "🏄♀",
  "suriname": "🇸🇷",
  "sushi": "🍣",
  "suspension_railway": "🚟",
  "svalbard_jan_mayen": "🇸🇯",
  "swan": "🦢",
  "swaziland": "🇸🇿",
  "sweat": "😓",
  "sweat_drops": "💦",
  "sweden": "🇸🇪",
  "sweet_potato": "🍠",
  "swim_brief": "🩲",
  "swimmer": "🏊",
  "swimming_man": "🏊♂",
  "swimming_woman": "🏊♀",
  "switzerland": "🇨🇭",
  "symbols": "🔣",
  "synagogue": "🕍",
  "syria": "🇸🇾",
  "syringe": "💉",
  "t-rex": "🦖",
  "taco": "🌮",
  "taiwan": "🇹🇼",
  "tajikistan": "🇹🇯",
  "takeout_box": "🥡",
  "tamale": "🫔",
  "tanabata_tree": "🎋",
  "tangerine": "🍊",
  "tanzania": "🇹🇿",
  "taurus": "♉",
  "taxi": "🚕",
  "tea": "🍵",
  "teacher": "🧑🏫",
  "teapot": "🫖",
  "technologist": "🧑💻",
  "teddy_bear": "🧸",
  "telephone": "☎",
  "telephone_receiver": "📞",
  "telescope": "🔭",
  "tennis": "🎾",
  "tent": "⛺",
  "test_tube": "🧪",
  "thailand": "🇹🇭",
  "thermometer": "🌡",
  "thong_sandal": "🩴",
  "thought_balloon": "💭",
  "thread": "🧵",
  "three": "3⃣",
  "thumbsdown": "👎",
  "thumbsup": "👍",
  "ticket": "🎫",
  "tickets": "🎟",
  "tiger": "🐯",
  "tiger2": "🐅",
  "timer_clock": "⏲",
  "timor_leste": "🇹🇱",
  "tipping_hand_man": "💁♂",
  "tipping_hand_person": "💁",
  "tipping_hand_woman": "💁♀",
  "tired_face": "😫",
  "tm": "™",
  "togo": "🇹🇬",
  "toilet": "🚽",
  "tokelau": "🇹🇰",
  "tokyo_tower": "🗼",
  "tomato": "🍅",
  "tonga": "🇹🇴",
  "tongue": "👅",
  "toolbox": "🧰",
  "tooth": "🦷",
  "toothbrush": "🪥",
  "top": "🔝",
  "tophat": "🎩",
  "tornado": "🌪",
  "tr": "🇹🇷",
  "trackball": "🖲",
  "tractor": "🚜",
  "traffic_light": "🚥",
  "train": "🚋",
  "train2": "🚆",
  "tram": "🚊",
  "transgender_flag": "🏳⚧",
  "transgender_symbol": "⚧",
  "triangular_flag_on_post": "🚩",
  "triangular_ruler": "📐",
  "trident": "🔱",
  "trinidad_tobago": "🇹🇹",
  "tristan_da_cunha": "🇹🇦",
  "triumph": "😤",
  "troll": "🧌",
  "trolleybus": "🚎",
  "trophy": "🏆",
  "tropical_drink": "🍹",
  "tropical_fish": "🐠",
  "truck": "🚚",
  "trumpet": "🎺",
  "tshirt": "👕",
  "tulip": "🌷",
  "tumbler_glass": "🥃",
  "tunisia": "🇹🇳",
  "turkey": "🦃",
  "turkmenistan": "🇹🇲",
  "turks_caicos_islands": "🇹🇨",
  "turtle": "🐢",
  "tuvalu": "🇹🇻",
  "tv": "📺",
  "twisted_rightwards_arrows": "🔀",
  "two": "2⃣",
  "two_hearts": "💕",
  "two_men_holding_hands": "👬",
  "two_women_holding_hands": "👭",
  "u5272": "🈹",
  "u5408": "🈴",
  "u55b6": "🈺",
  "u6307": "🈯",
  "u6708": "🈷",
  "u6709": "🈶",
  "u6e80": "🈵",
  "u7121": "🈚",
  "u7533": "🈸",
  "u7981": "🈲",
  "u7a7a": "🈳",
  "uganda": "🇺🇬",
  "uk": "🇬🇧",
  "ukraine": "🇺🇦",
  "umbrella": "☔",
  "unamused": "😒",
  "underage": "🔞",
  "unicorn": "🦄",
  "united_arab_emirates": "🇦🇪",
  "united_nations": "🇺🇳",
  "unlock": "🔓",
  "up": "🆙",
  "upside_down_face": "🙃",
  "uruguay": "🇺🇾",
  "us": "🇺🇸",
  "us_outlying_islands": "🇺🇲",
  "us_virgin_islands": "🇻🇮",
  "uzbekistan": "🇺🇿",
  "v": "✌",
  "vampire": "🧛",
  "vampire_man": "🧛♂",
  "vampire_woman": "🧛♀",
  "vanuatu": "🇻🇺",
  "vatican_city": "🇻🇦",
  "venezuela": "🇻🇪",
  "vertical_traffic_light": "🚦",
  "vhs": "📼",
  "vibration_mode": "📳",
  "video_camera": "📹",
  "video_game": "🎮",
  "vietnam": "🇻🇳",
  "violin": "🎻",
  "virgo": "♍",
  "volcano": "🌋",
  "volleyball": "🏐",
  "vomiting_face": "🤮",
  "vs": "🆚",
  "vulcan_salute": "🖖",
  "waffle": "🧇",
  "wales": "🏴󠁧󠁢󠁷󠁬󠁳󠁿",
  "walking": "🚶",
  "walking_man": "🚶♂",
  "walking_woman": "🚶♀",
  "wallis_futuna": "🇼🇫",
  "waning_crescent_moon": "🌘",
  "waning_gibbous_moon": "🌖",
  "wastebasket": "🗑",
  "watch": "⌚",
  "water_buffalo": "🐃",
  "water_polo": "🤽",
  "watermelon": "🍉",
  "wavy_dash": "〰",
  "waxing_crescent_moon": "🌒",
  "waxing_gibbous_moon": "🌔",
  "wc": "🚾",
  "weary": "😩",
  "wedding": "💒",
  "weight_lifting": "🏋",
  "weight_lifting_man": "🏋♂",
  "weight_lifting_woman": "🏋♀",
  "western_sahara": "🇪🇭",
  "whale": "🐳",
  "whale2": "🐋",
  "wheel": "🛞",
  "wheel_of_dharma": "☸",
  "wheelchair": "♿",
  "white_check_mark": "✅",
  "white_circle": "⚪",
  "white_flag": "🏳",
  "white_flower": "💮",
  "white_haired_man": "👨🦳",
  "white_haired_woman": "👩🦳",
  "white_heart": "🤍",
  "white_large_square": "⬜",
  "white_medium_small_square": "◽",
  "white_medium_square": "◻",
  "white_small_square": "▫",
  "white_square_button": "🔳",
  "wilted_flower": "🥀",
  "wind_chime": "🎐",
  "wind_face": "🌬",
  "window": "🪟",
  "wine_glass": "🍷",
  "wing": "🪽",
  "wink": "😉",
  "wireless": "🛜",
  "wolf": "🐺",
  "woman": "👩",
  "woman_artist": "👩🎨",
  "woman_astronaut": "👩🚀",
  "woman_beard": "🧔♀",
  "woman_cartwheeling": "🤸♀",
  "woman_cook": "👩🍳",
  "woman_dancing": "💃",
  "woman_facepalming": "🤦♀",
  "woman_factory_worker": "👩🏭",
  "woman_farmer": "👩🌾",
  "woman_feeding_baby": "👩🍼",
  "woman_firefighter": "👩🚒",
  "woman_health_worker": "👩⚕",
  "woman_in_manual_wheelchair": "👩🦽",
  "woman_in_motorized_wheelchair": "👩🦼",
  "woman_in_tuxedo": "🤵♀",
  "woman_judge": "👩⚖",
  "woman_juggling": "🤹♀",
  "woman_mechanic": "👩🔧",
  "woman_office_worker": "👩💼",
  "woman_pilot": "👩✈",
  "woman_playing_handball": "🤾♀",
  "woman_playing_water_polo": "🤽♀",
  "woman_scientist": "👩🔬",
  "woman_shrugging": "🤷♀",
  "woman_singer": "👩🎤",
  "woman_student": "👩🎓",
  "woman_teacher": "👩🏫",
  "woman_technologist": "👩💻",
  "woman_with_headscarf": "🧕",
  "woman_with_probing_cane": "👩🦯",
  "woman_with_turban": "👳♀",
  "woman_with_veil": "👰♀",
  "womans_clothes": "👚",
  "womans_hat": "👒",
  "women_wrestling": "🤼♀",
  "womens": "🚺",
  "wood": "🪵",
  "woozy_face": "🥴",
  "world_map": "🗺",
  "worm": "🪱",
  "worried": "😟",
  "wrestling": "🤼",
  "writing_hand": "✍",
  "x_ray": "🩻",
  "yarn": "🧶",
  "yawning_face": "🥱",
  "yellow_circle": "🟡",
  "yellow_heart": "💛",
  "yellow_square": "🟨",
  "yemen": "🇾🇪",
  "yen": "💴",
  "yin_yang": "☯",
  "yo_yo": "🪀",
  "yum": "😋",
  "zambia": "🇿🇲",
  "zany_face": "🤪",
  "zap": "⚡",
  "zebra": "🦓",
  "zero": "0⃣",
  "zimbabwe": "🇿🇼",
  "zipper_mouth_face": "🤐",
  "zombie": "🧟",
  "zombie_man": "🧟♂",
  "zombie_woman": "🧟♀",
  "zzz": "💤",
  "database": "🗄️",
  "db": "🗄️",
  "server": "🖥️",
  "network": "🌐",
  "firewall": "🛡️",
  "k8s": "☸️",
  "kubernetes": "☸️",
  "docker": "🐳"
};

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

    // 5. Replace :shortcode: if in GITHUB_EMOJI_MAP
    processed = processed.replace(/:([a-zA-Z0-9_+-]+):/g, function(match, code) {
      if (Object.prototype.hasOwnProperty.call(GITHUB_EMOJI_MAP, code)) {
        return GITHUB_EMOJI_MAP[code];
      }
      const lower = code.toLowerCase();
      if (Object.prototype.hasOwnProperty.call(GITHUB_EMOJI_MAP, lower)) {
        return GITHUB_EMOJI_MAP[lower];
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
  root.GITHUB_EMOJI_LIST = GITHUB_EMOJI_LIST;
  root.GITHUB_EMOJI_MAP = GITHUB_EMOJI_MAP;
  root.MARKDOWN_EMOJI_LIST = GITHUB_EMOJI_LIST;
  root.MD_EMOJI_MAP = GITHUB_EMOJI_MAP;
  root.replaceEmojiShortcodes = replaceEmojiShortcodes;
  root.replaceGitHubEmojis = replaceEmojiShortcodes;

})(typeof window !== 'undefined' ? window : this);
