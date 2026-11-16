// Run with: node --test scripts/app-store-listing.test.mjs
// The App Store page in mobile/ios/fastlane/: each file Apple needs, within Apple's limits, with no private detail.
import assert from 'node:assert/strict';
import test from 'node:test';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const FASTLANE = new URL('../mobile/ios/fastlane/', import.meta.url).pathname;
const METADATA = join(FASTLANE, 'metadata');
const LOCALE = 'en-CA';
const SCREENSHOTS = join(FASTLANE, 'screenshots', LOCALE);

// Apple's character limits; a file with no limit here has none to check.
const LIMITS = {
  [`${LOCALE}/name.txt`]: 30,
  [`${LOCALE}/subtitle.txt`]: 30,
  [`${LOCALE}/keywords.txt`]: 100,
  [`${LOCALE}/promotional_text.txt`]: 170,
  [`${LOCALE}/description.txt`]: 4000,
  [`${LOCALE}/support_url.txt`]: null,
  [`${LOCALE}/marketing_url.txt`]: null,
  [`${LOCALE}/privacy_url.txt`]: null,
  'copyright.txt': null,
  'primary_category.txt': null,
  'secondary_category.txt': null,
  'review_information/notes.txt': 4000,
};
const URLS = ['support_url.txt', 'marketing_url.txt', 'privacy_url.txt'].map(name => `${LOCALE}/${name}`);

// deliver's category names (Spaceship::ConnectAPI::AppCategory), less the game and sticker subcategories.
const CATEGORIES = new Set(['BOOKS', 'BUSINESS', 'DEVELOPER_TOOLS', 'EDUCATION', 'ENTERTAINMENT', 'FINANCE',
  'FOOD_AND_DRINK', 'GAMES', 'GRAPHICS_AND_DESIGN', 'HEALTH_AND_FITNESS', 'LIFESTYLE', 'MAGAZINES_AND_NEWSPAPERS',
  'MEDICAL', 'MUSIC', 'NAVIGATION', 'NEWS', 'PHOTO_AND_VIDEO', 'PRODUCTIVITY', 'REFERENCE', 'SHOPPING',
  'SOCIAL_NETWORKING', 'SPORTS', 'STICKERS', 'TRAVEL', 'UTILITIES', 'WEATHER']);

// Apple's age rating questions (Spaceship::ConnectAPI::AgeRatingDeclaration): how often, or yes or no.
const RATING_LEVELS = new Set(['NONE', 'INFREQUENT_OR_MILD', 'FREQUENT_OR_INTENSE']);
const LEVEL_KEYS = ['alcoholTobaccoOrDrugUseOrReferences', 'contests', 'gamblingSimulated', 'gunsOrOtherWeapons',
  'horrorOrFearThemes', 'matureOrSuggestiveThemes', 'medicalOrTreatmentInformation', 'profanityOrCrudeHumor',
  'sexualContentGraphicAndNudity', 'sexualContentOrNudity', 'violenceCartoonOrFantasy', 'violenceRealistic',
  'violenceRealisticProlongedGraphicOrSadistic'];
const YES_NO_KEYS = ['advertising', 'ageAssurance', 'gambling', 'healthOrWellnessTopics', 'lootBox', 'messagingAndChat',
  'parentalControls', 'socialMedia', 'socialMediaAgeRestricted', 'unrestrictedWebAccess', 'userGeneratedContent'];

// The sizes App Store Connect takes for each device the app needs, portrait, from deliver's DEVICE_RESOLUTIONS.
const DEVICES = {
  'iPhone 6.9-inch': [[1260, 2736], [1290, 2796], [1320, 2868]],
  'iPad 13-inch': [[2048, 2732], [2064, 2752]],
  'Apple Watch': [[410, 502], [422, 514], [416, 496], [396, 484]],
};
const MAX_PER_DEVICE = 10;

// The same patterns as scripts/public-check.mjs: the repository is public.
const EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}/;
const PHONE = /(?<![\w.:/-])(?:\+\d{1,3}[\s.-]?)?(?:\(\d{3}\)\s?|\d{3}[\s.-])\d{3}[\s.-]\d{4}(?![\w.-])/;

const read = path => readFileSync(join(METADATA, path), 'utf8').trim();

/** Every metadata file, as a path from the metadata folder. */
function metadataFiles(dir = METADATA, prefix = '') {
  return readdirSync(dir, { withFileTypes: true }).flatMap(entry => entry.isDirectory()
    ? metadataFiles(join(dir, entry.name), `${prefix}${entry.name}/`) : [`${prefix}${entry.name}`]);
}

/** A PNG's width and height, from its IHDR header; null for any other file. */
export function pngSize(buffer) {
  const signature = '89504e470d0a1a0a';
  if (buffer.length < 24 || buffer.subarray(0, 8).toString('hex') !== signature) return null;
  return [buffer.readUInt32BE(16), buffer.readUInt32BE(20)];
}

/** The device a screenshot of this size is for, or null when App Store Connect takes no such size. */
export function deviceFor([width, height]) {
  const [short, long] = width < height ? [width, height] : [height, width];
  return Object.keys(DEVICES).find(device => DEVICES[device].some(([w, h]) => w === short && h === long)) ?? null;
}

/** Each problem with the screenshots in `files` ({ name, buffer }), as a line naming the file. */
export function screenshotProblems(files) {
  const problems = [];
  const counts = Object.fromEntries(Object.keys(DEVICES).map(device => [device, 0]));
  for (const { name, buffer } of files) {
    const size = pngSize(buffer);
    const device = size && deviceFor(size);
    if (!size) problems.push(`${name}: not a PNG`);
    else if (!device) problems.push(`${name}: ${size.join('×')} is no size App Store Connect takes`);
    else counts[device] += 1;
  }
  for (const [device, count] of Object.entries(counts)) {
    if (count === 0) problems.push(`no screenshot for ${device}`);
    if (count > MAX_PER_DEVICE) problems.push(`${count} screenshots for ${device}; Apple takes ${MAX_PER_DEVICE}`);
  }
  return problems;
}

/** A PNG header of the given size, enough for pngSize. */
const fakePng = (width, height) => {
  const buffer = Buffer.alloc(24);
  Buffer.from('89504e470d0a1a0a', 'hex').copy(buffer);
  buffer.writeUInt32BE(width, 16);
  buffer.writeUInt32BE(height, 20);
  return buffer;
};

test('each page file Apple needs is there, and within its limit', () => {
  for (const [path, limit] of Object.entries(LIMITS)) {
    assert.ok(existsSync(join(METADATA, path)), `metadata/${path} is missing`);
    const text = read(path);
    assert.ok(text.length > 0, `metadata/${path} is empty`);
    if (limit) assert.ok(text.length <= limit, `metadata/${path} has ${text.length} characters; Apple takes ${limit}`);
  }
  assert.equal(read(`${LOCALE}/name.txt`), 'Relay Everything');
});

test('the page links are https, and the privacy link is the website\'s Privacy page', () => {
  for (const path of URLS) assert.match(read(path), /^https:\/\/\S+$/, `metadata/${path}`);
  assert.equal(read(`${LOCALE}/privacy_url.txt`), 'https://relayeverything.com/privacy/');
});

test('the categories are names deliver knows', () => {
  for (const path of ['primary_category.txt', 'secondary_category.txt']) {
    assert.ok(CATEGORIES.has(read(path)), `metadata/${path}: ${read(path)} is not a category deliver knows`);
  }
});

test('each age rating answer is a question Apple asks, with an answer it takes', () => {
  const rating = JSON.parse(readFileSync(join(FASTLANE, 'rating.json'), 'utf8'));
  for (const [key, value] of Object.entries(rating)) {
    if (LEVEL_KEYS.includes(key)) assert.ok(RATING_LEVELS.has(value), `rating.json: ${key} is ${value}`);
    else if (YES_NO_KEYS.includes(key)) assert.equal(typeof value, 'boolean', `rating.json: ${key}`);
    else assert.fail(`rating.json: ${key} is not an age rating question`);
  }
  for (const key of LEVEL_KEYS) assert.ok(key in rating, `rating.json does not answer ${key}`);
});

test('the privacy answers say what is collected, linked to the person, for the app only, with no tracking', () => {
  const answers = JSON.parse(readFileSync(join(FASTLANE, 'app_privacy_details.json'), 'utf8'));
  assert.deepEqual(answers.map(answer => answer.category).sort(), ['DEVICE_ID', 'EMAIL_ADDRESS', 'FITNESS', 'HEALTH',
    'OTHER_USER_CONTENT', 'PHOTOS_OR_VIDEOS', 'PRECISE_LOCATION', 'USER_ID']);
  for (const answer of answers) {
    assert.deepEqual(answer.purposes, ['APP_FUNCTIONALITY'], answer.category);
    assert.deepEqual(answer.data_protections, ['DATA_LINKED_TO_YOU'], answer.category);
  }
});

test('no page file holds an email address or a phone number', () => {
  for (const path of metadataFiles()) {
    const text = read(path);
    assert.doesNotMatch(text, EMAIL, `metadata/${path} holds an email address`);
    assert.doesNotMatch(text, PHONE, `metadata/${path} holds a phone number`);
  }
});

test('a screenshot of a size Apple does not take, or a device with none, is refused', () => {
  const good = [['1_iphone.png', 1320, 2868], ['1_ipad.png', 2064, 2752], ['1_watch.png', 422, 514]]
    .map(([name, w, h]) => ({ name, buffer: fakePng(w, h) }));
  assert.deepEqual(screenshotProblems(good), []);
  assert.deepEqual(screenshotProblems([...good, { name: 'x.png', buffer: fakePng(1179, 2556) }]),
    ['x.png: 1179×2556 is no size App Store Connect takes']);
  assert.deepEqual(screenshotProblems([{ name: 'a.png', buffer: Buffer.from('jpeg') }, good[0], good[1]]),
    ['a.png: not a PNG', 'no screenshot for Apple Watch']);
  const many = Array.from({ length: 11 }, (_, n) => ({ name: `${n}.png`, buffer: fakePng(2868, 1320) }));
  assert.ok(screenshotProblems([...many, good[1], good[2]]).includes('11 screenshots for iPhone 6.9-inch; Apple takes 10'));
});

test('the screenshots cover iPhone, iPad and Apple Watch, each at a size Apple takes', () => {
  const names = existsSync(SCREENSHOTS) ? readdirSync(SCREENSHOTS).filter(name => !name.startsWith('.')) : [];
  const files = names.map(name => ({ name, buffer: readFileSync(join(SCREENSHOTS, name)) }));
  const problems = screenshotProblems(files);
  assert.deepEqual(problems, [], `Fix screenshots/${LOCALE}/ (mobile/README.md#the-app-store-page):\n${problems.join('\n')}`);
});
