const { PGlite } = require(process.env.KD_PGLITE_MODULE || '@electric-sql/pglite');
const fs = require('fs');
const assert = require('node:assert/strict');
const ids = Array.from({length:10},(_,i)=>`00000000-0000-4000-8000-${String(i+1).padStart(12,'0')}`);
const request='10000000-0000-4000-8000-000000000001';
const pledge='20000000-0000-4000-8000-000000000001';
const shipment='30000000-0000-4000-8000-000000000001';
let passed=0;
const db=new PGlite();
async function check(name,fn){await fn();passed++;console.log('PASS '+name)}
async function as(i,fn){await db.exec(`RESET ROLE; SELECT set_config('request.jwt.claim.sub','${i===null?'':ids[i]}',false); SET ROLE ${i===null?'anon':'authenticated'}`);try{return await fn()}finally{await db.exec('RESET ROLE')}}
async function rpc(i,action,data={}){return as(i,async()=> (await db.query('SELECT public.kd_api($1,$2::jsonb) AS value',[action,JSON.stringify(data)])).rows[0].value)}
async function denied(i,action,data,pattern){await assert.rejects(()=>rpc(i,action,data),pattern)}
async function main(){
await db.exec(`CREATE ROLE anon; CREATE ROLE authenticated; CREATE SCHEMA auth;
CREATE TABLE auth.users(id uuid PRIMARY KEY,email text,email_confirmed_at timestamptz,banned_until timestamptz);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
GRANT USAGE ON SCHEMA public,auth TO anon,authenticated; GRANT EXECUTE ON FUNCTION auth.uid() TO anon,authenticated;
CREATE TABLE public.book_requests(id text PRIMARY KEY); INSERT INTO public.book_requests VALUES('legacy-1');
CREATE TABLE public.pledges(id text PRIMARY KEY); INSERT INTO public.pledges VALUES('legacy-pledge');
ALTER TABLE public.book_requests ENABLE ROW LEVEL SECURITY; CREATE POLICY insecure ON public.book_requests FOR ALL USING(true) WITH CHECK(true);
GRANT ALL ON public.book_requests,public.pledges TO anon,authenticated;`);
for(let i=0;i<ids.length;i++)await db.query('INSERT INTO auth.users VALUES($1,$2,$3,null)',[ids[i],i===7?'school@demo.pk':`fixture${i}@example.invalid`,i===6?null:new Date().toISOString()]);
const sql=fs.readFileSync(require('node:path').join(__dirname,'production-schema.sql'),'utf8');
await check('migration executes and is repeatable',async()=>{await db.exec(sql);await db.exec(sql)});
await check('legacy records preserved',async()=>assert.equal((await db.query('SELECT count(*)::int AS n FROM book_requests')).rows[0].n,1));
await check('anonymous direct table reads and writes denied',async()=>{for(const t of ['book_requests','pledges','kd_profiles','kd_requests','kd_pledges','kd_shipments','kd_events','kd_issues'])await as(null,()=>assert.rejects(()=>db.query(`SELECT * FROM public.${t}`),/permission denied/));await as(null,()=>assert.rejects(()=>db.query("INSERT INTO book_requests VALUES('intruder')"),/permission denied/))});
await check('private helper inaccessible',()=>as(null,()=>assert.rejects(()=>db.query('SELECT public.kd_public_request($1)',[request]),/permission denied/)));
await check('no profile is null',async()=>assert.equal((await rpc(0,'me')).profile,null));
await check('anonymous, unconfirmed and retired demo accounts denied',async()=>{for(const i of [null,6,7])await denied(i,'profile',{},/confirmed, active/)});
await check('self-appointed admin rejected',()=>denied(0,'profile',{role:'admin'},/school or donor/));
for(let i=0;i<6;i++)await rpc(i,'profile',{role:i<2?'school':'ngo',organization:i<2?'Same School':'Donor '+i,person:'Test Contact',phone:'+923000000000',city:'Lahore'});
await db.query("INSERT INTO kd_admins(user_id) VALUES($1)",[ids[5]]);
await check('ordinary account cannot approve itself',()=>denied(2,'admin_review',{user_id:ids[2],decision:'approve',note:'Pretended verification'},/Administrator/));
for(let i=0;i<4;i++)await rpc(5,'admin_review',{user_id:ids[i],decision:'approve',note:'Verified isolated test fixture'});
const data={id:request,retry_create:true,title:'Science Grade 8',description:'Forty science books for classroom use.',subject:'Science',grade:'8',board:'Punjab',language:'English',edition:'2026',condition:'Good used copies accepted',needed_by:'2099-01-01',quantity:40,urgency:'High',address:'Private gate address, Lahore',emis:'12345678'};
await check('school create and retry are idempotent',async()=>{await rpc(0,'request_save',data);await rpc(0,'request_save',data);assert.equal((await db.query('SELECT count(*)::int n FROM kd_requests')).rows[0].n,1)});
await check('same name does not confer ownership',()=>denied(1,'request_save',{...data,version:1},/Not your request/));
await check('profile metadata cannot change stored role or organization',async()=>{const p=await rpc(0,'profile',{role:'admin',organization:'Fake',person:'Contact Person',phone:'+923000000000',city:'Lahore'});assert.equal(p.role,'school');assert.equal(p.organization,'Same School')});
await check('public catalog has no contacts or full address',async()=>{const r=await rpc(null,'catalog');assert.equal(r.total,1);assert.ok(!/phone|person|address|owner_id|donor_id/.test(JSON.stringify(r)));assert.equal((await rpc(null,'catalog',{search:'no match'})).items.length,0)});
await check('unapproved donor cannot pledge',()=>denied(4,'pledge',{id:pledge,request_id:request,quantity:30},/approved donor/));
await check('pledge and retry reserve once',async()=>{await rpc(2,'pledge',{id:pledge,request_id:request,quantity:30});await rpc(2,'pledge',{id:pledge,request_id:request,quantity:30});assert.equal((await rpc(null,'detail',{id:request})).pledged,30)});
await check('overpledging rejected atomically',()=>denied(3,'pledge',{id:'20000000-0000-4000-8000-000000000002',request_id:request,quantity:30},/Available quantity/));
await check('active pledge prevents request changes',()=>denied(0,'request_cancel',{id:request,version:1},/Active pledges/));
await check('unrelated account has no private workspace rows',async()=>assert.equal((await rpc(3,'workspace')).pledges.length,0));
await check('donor cannot change other donor pledge',()=>denied(3,'pledge_edit',{pledge_id:pledge,quantity:20,version:1},/Not your pledge/));
await check('dispatch limited to own pledge quantity',()=>denied(2,'dispatch',{id:shipment,pledge_id:pledge,quantity:40,carrier:'Courier',tracking:'TEST-1'},/exceeds/));
await check('partial parcel and retry tracked once',async()=>{const d={id:shipment,pledge_id:pledge,quantity:12,carrier:'Courier',tracking:'TEST-1'};await rpc(2,'dispatch',d);await rpc(2,'dispatch',d);const s=await rpc(null,'stats');assert.equal(s.dispatched,12);assert.equal(s.received,0)});
await check('donor and other school cannot confirm receipt',async()=>{for(const i of [1,2])await denied(i,'receive',{id:shipment,received_quantity:12,version:1},/receiving school/)});
await check('partial receipt does not create a pledge',async()=>{await rpc(0,'receive',{id:shipment,received_quantity:10,version:1,note:'Two books are still missing',issue:true});const s=await rpc(null,'stats');assert.equal(s.received,10);assert.equal(s.pledged,30);assert.equal((await db.query('SELECT count(*)::int n FROM kd_pledges')).rows[0].n,1)});
await check('stale receipt and over-receipt rejected',async()=>{await denied(0,'receive',{id:shipment,received_quantity:12,version:1},/Receipt changed/);await denied(0,'receive',{id:shipment,received_quantity:13,version:2},/between/)});
await check('receipt retry is idempotent',async()=>{await rpc(0,'receive',{id:shipment,received_quantity:10,version:1,note:'Two books are still missing',issue:true});assert.equal((await rpc(null,'stats')).received,10)});
await check('shipped pledge cannot be cancelled or reduced below shipped',async()=>{await denied(2,'pledge_cancel',{pledge_id:pledge,version:1},/dispatched pledge/);await denied(2,'pledge_edit',{pledge_id:pledge,version:1,quantity:2},/conflicts/)});
await check('verification suspension blocks stale session',async()=>{await rpc(5,'admin_review',{user_id:ids[3],decision:'suspend',note:'Account fixture suspension'});await denied(3,'workspace',{},/suspended/)});
await check('only admin can transfer authority',()=>denied(2,'admin_transfer',{email:'fixture4@example.invalid'},/Administrator/));
await check('administrator transfer revokes old and grants new account',async()=>{await rpc(5,'admin_transfer',{email:'fixture4@example.invalid'});await denied(5,'admin_queue',{},/Administrator/);assert.equal((await rpc(4,'me')).is_admin,true)});
console.log(`RESULT: ${passed} security and workflow checks passed`);
await db.close();
}
main().catch(e=>{console.error(e);process.exit(1)});
