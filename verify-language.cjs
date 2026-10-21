// Optional regression checks; the deployed page still requires no build step.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const html=fs.readFileSync(path.join(__dirname,'index.html'),'utf8');
const source=[...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].at(-1)[1];
function boot(saved,blocked=false){
 const storage={kd_language:saved},doc={documentElement:{},querySelector:()=>null};
 const ctx=vm.createContext({React:{createElement:()=>{}},document:doc,localStorage:{getItem:k=>{if(blocked)throw Error('blocked');return storage[k]},setItem:(k,v)=>{if(blocked)throw Error('blocked');storage[k]=v}}});
 vm.runInContext(source.split('const db=')[0],ctx);return{ctx,doc,storage,run:code=>vm.runInContext(code,ctx)};
}
const a=boot('en');assert.equal(a.doc.documentElement.dir,'ltr');
a.run('changeLanguage()');assert.equal(a.doc.documentElement.lang,'ur');assert.equal(a.doc.documentElement.dir,'rtl');assert.equal(a.storage.kd_language,'ur');
assert.equal(a.run("t('Sign in')"),'سائن اِن');
assert.equal(a.run("t('{count} books pledged',{count:12})"),'12 کتابوں کا وعدہ');
assert.equal(a.run("eventText('Fixture School pledged 2 books.')"),'Fixture School نے 2 کتابیں دینے کا وعدہ کیا۔');
assert.equal(a.run("t('Unknown user-authored string')"),'Unknown user-authored string');
a.run('changeLanguage()');assert.equal(a.run("t('Sign in')"),'Sign in');
assert.equal(boot('ur').doc.documentElement.dir,'rtl');assert.equal(boot('invalid').doc.documentElement.lang,'en');
const blocked=boot(null,true);blocked.run('changeLanguage()');assert.equal(blocked.doc.documentElement.lang,'ur');
assert.ok(html.includes('className:\'brand-se\''));
assert.ok(!source.includes('The legacy requests and pledges are preserved'));
console.log('PASS language persistence, blocked storage, RTL metadata, translated messages, interpolation and branding');
