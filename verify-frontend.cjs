// Optional maintainer check. Serving the website does not require Node.
const fs=require('node:fs'),crypto=require('node:crypto'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync(require('node:path').join(__dirname,'index.html'),'utf8').replace(/\r\n?/g,'\n');
const scripts=[...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m=>m[1]);
assert.equal(scripts.length,4);
const policy=html.match(/http-equiv="Content-Security-Policy" content="([^"]+)"/)[1];
for(const source of scripts){new vm.Script(source);const hash=crypto.createHash('sha256').update(source).digest('base64');assert.ok(policy.includes("'sha256-"+hash+"'"),'Script CSP hash mismatch')}
assert.ok(!/<script[^>]+src=|type="text\/babel"|cdn\.tailwindcss\.com/.test(html));
assert.ok(!policy.includes('unsafe-eval'));
assert.ok(!/script-src[^;]*unsafe-inline/.test(policy));
assert.ok(!/\.from\(['"](?:book_requests|pledges|kd_)/.test(scripts[3]));
assert.ok(!/dangerouslySetInnerHTML|innerHTML\s*=/.test(scripts[3]));
console.log('PASS: script syntax, four matching CSP hashes, no runtime compilation/CDN scripts, no unsafe script policy or raw HTML insertion');
