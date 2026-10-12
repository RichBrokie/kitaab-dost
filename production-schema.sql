-- Kitaab Dost security migration v2. Run as the project database owner.
-- Atomic, repeatable, preserves legacy rows; never infer ownership from names.
BEGIN;
CREATE TABLE IF NOT EXISTS public.kd_admins (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.kd_profiles (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id),
  role text NOT NULL CHECK (role IN ('school','ngo','admin')),
  organization text NOT NULL CHECK (length(trim(organization)) BETWEEN 2 AND 160),
  person text NOT NULL CHECK (length(trim(person)) BETWEEN 2 AND 120),
  phone text NOT NULL CHECK (phone ~ '^\+92[0-9]{10}$'),
  city text NOT NULL CHECK (length(trim(city)) BETWEEN 2 AND 120),
  verified_at timestamptz,
  verified_by uuid REFERENCES auth.users(id),
  review_note text NOT NULL DEFAULT '',
  disabled boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.kd_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.kd_profiles(user_id),
  title text NOT NULL CHECK (length(trim(title)) BETWEEN 3 AND 180),
  description text NOT NULL CHECK (length(trim(description)) BETWEEN 10 AND 2000),
  subject text NOT NULL CHECK (length(subject) BETWEEN 2 AND 60),
  grade text NOT NULL CHECK (length(grade) BETWEEN 1 AND 60),
  board text NOT NULL CHECK (length(board) BETWEEN 2 AND 80),
  language text NOT NULL CHECK (length(language) BETWEEN 2 AND 40),
  edition text NOT NULL CHECK (length(edition) BETWEEN 1 AND 80),
  condition text NOT NULL CHECK (condition IN ('New only','Good used copies accepted')),
  needed_by date NOT NULL,
  quantity integer NOT NULL CHECK (quantity BETWEEN 1 AND 5000),
  urgency text NOT NULL CHECK (urgency IN ('Critical','High','Medium')),
  address text NOT NULL CHECK (length(trim(address)) BETWEEN 10 AND 500),
  emis text NOT NULL DEFAULT '' CHECK (emis='' OR emis ~ '^[0-9]{7,12}$'),
  cancelled boolean NOT NULL DEFAULT false,
  version integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.kd_pledges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.kd_requests(id),
  donor_id uuid NOT NULL REFERENCES public.kd_profiles(user_id),
  quantity integer NOT NULL CHECK (quantity BETWEEN 1 AND 5000),
  note text NOT NULL DEFAULT '' CHECK (length(note)<=1000),
  cancelled boolean NOT NULL DEFAULT false,
  version integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.kd_shipments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pledge_id uuid NOT NULL REFERENCES public.kd_pledges(id),
  quantity integer NOT NULL CHECK (quantity BETWEEN 1 AND 5000),
  carrier text NOT NULL CHECK (length(trim(carrier)) BETWEEN 2 AND 100),
  tracking text NOT NULL CHECK (length(trim(tracking)) BETWEEN 2 AND 120),
  sender_name text NOT NULL,
  sender_person text NOT NULL,
  sender_phone text NOT NULL,
  sender_city text NOT NULL,
  receiver_name text NOT NULL,
  receiver_person text NOT NULL,
  receiver_phone text NOT NULL,
  receiver_address text NOT NULL,
  received_quantity integer NOT NULL DEFAULT 0 CHECK (received_quantity BETWEEN 0 AND quantity),
  receipt_note text NOT NULL DEFAULT '' CHECK (length(receipt_note)<=1000),
  issue boolean NOT NULL DEFAULT false,
  version integer NOT NULL DEFAULT 1,
  dispatched_at timestamptz NOT NULL DEFAULT now(),
  received_at timestamptz
);
CREATE TABLE IF NOT EXISTS public.kd_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor_id uuid NOT NULL REFERENCES auth.users(id),
  recipient_id uuid NOT NULL REFERENCES auth.users(id),
  request_id uuid REFERENCES public.kd_requests(id),
  message text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.kd_issues (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id),
  request_id uuid REFERENCES public.kd_requests(id),
  message text NOT NULL CHECK (length(trim(message)) BETWEEN 10 AND 2000),
  resolved boolean NOT NULL DEFAULT false,
  response text NOT NULL DEFAULT '' CHECK (length(response)<=2000),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS kd_requests_owner ON public.kd_requests(owner_id);
CREATE INDEX IF NOT EXISTS kd_requests_newest ON public.kd_requests(created_at DESC,id);
CREATE INDEX IF NOT EXISTS kd_pledges_request ON public.kd_pledges(request_id);
CREATE INDEX IF NOT EXISTS kd_pledges_donor ON public.kd_pledges(donor_id);
CREATE INDEX IF NOT EXISTS kd_shipments_pledge ON public.kd_shipments(pledge_id);
CREATE INDEX IF NOT EXISTS kd_events_recipient ON public.kd_events(recipient_id,created_at DESC);

-- No direct client table access, including SELECT on contact-bearing rows.
-- The narrowly projected RPC below is the entire client API.
DO $secure$
DECLARE t text; p record;
BEGIN
  FOREACH t IN ARRAY ARRAY['kd_admins','kd_profiles','kd_requests','kd_pledges','kd_shipments','kd_events','kd_issues','book_requests','pledges'] LOOP
    IF to_regclass('public.'||t) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
      EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon, authenticated',t);
      FOR p IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename=t LOOP
        EXECUTE format('DROP POLICY %I ON public.%I',p.policyname,t);
      END LOOP;
    END IF;
  END LOOP;
END $secure$;
REVOKE ALL ON SEQUENCE public.kd_events_id_seq FROM PUBLIC, anon, authenticated;

-- Retire shared production demo accounts, preserving account and data history.
UPDATE auth.users SET banned_until='2126-10-13 00:00:00+00'::timestamptz
WHERE lower(email) IN ('school@demo.pk','ngo@demo.pk');

CREATE OR REPLACE FUNCTION public.kd_public_request(p_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $fn$
  SELECT jsonb_build_object('id',r.id,'school',u.organization,'city',u.city,
    'verified',u.verified_at IS NOT NULL,'title',r.title,'description',r.description,
    'subject',r.subject,'grade',r.grade,'board',r.board,'language',r.language,
    'edition',r.edition,'condition',r.condition,'needed_by',r.needed_by,
    'quantity',r.quantity,'urgency',r.urgency,'emis',r.emis,'cancelled',r.cancelled,
    'version',r.version,'created_at',r.created_at,
    'pledged',COALESCE((SELECT sum(p.quantity) FROM public.kd_pledges p WHERE p.request_id=r.id AND NOT p.cancelled),0),
    'dispatched',COALESCE((SELECT sum(s.quantity) FROM public.kd_shipments s JOIN public.kd_pledges p ON p.id=s.pledge_id WHERE p.request_id=r.id),0),
    'received',COALESCE((SELECT sum(s.received_quantity) FROM public.kd_shipments s JOIN public.kd_pledges p ON p.id=s.pledge_id WHERE p.request_id=r.id),0))
  FROM public.kd_requests r JOIN public.kd_profiles u ON u.user_id=r.owner_id WHERE r.id=p_id;
$fn$;
REVOKE ALL ON FUNCTION public.kd_public_request(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.kd_api(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  uid uuid := auth.uid(); actor public.kd_profiles; school public.kd_profiles; is_admin boolean;
  r public.kd_requests; p public.kd_pledges; s public.kd_shipments;
  ident uuid; rid uuid; result jsonb; items jsonb; n integer; used integer;
  page_no integer; page_size integer := 12; total bigint; q text; scope text;
BEGIN
  IF p_action IN ('catalog','stats','detail','health') THEN
    IF p_action='health' THEN RETURN jsonb_build_object('version',2); END IF;
    IF p_action='detail' THEN
      SELECT * INTO r FROM public.kd_requests WHERE id=(p_data->>'id')::uuid;
      IF r.id IS NULL OR r.cancelled OR NOT EXISTS(SELECT 1 FROM public.kd_profiles WHERE user_id=r.owner_id AND verified_at IS NOT NULL AND NOT disabled) THEN
        RAISE EXCEPTION 'Request is unavailable'; END IF;
      RETURN public.kd_public_request(r.id);
    END IF;
    IF p_action='stats' THEN
      SELECT jsonb_build_object('requested',COALESCE(sum((j->>'quantity')::bigint),0),
        'pledged',COALESCE(sum((j->>'pledged')::bigint),0),'dispatched',COALESCE(sum((j->>'dispatched')::bigint),0),
        'received',COALESCE(sum((j->>'received')::bigint),0),'requests',count(*),
        'schools',count(DISTINCT owner_id)) INTO result
      FROM (SELECT r0.owner_id,public.kd_public_request(r0.id) j FROM public.kd_requests r0
        JOIN public.kd_profiles u ON u.user_id=r0.owner_id WHERE NOT r0.cancelled AND NOT u.disabled AND u.verified_at IS NOT NULL) x;
      RETURN result;
    END IF;
    page_no := greatest(0,least(10000,COALESCE((p_data->>'page')::integer,0)));
    q := left(COALESCE(p_data->>'search',''),120);
    WITH matches AS (
      SELECT r0.id,r0.created_at FROM public.kd_requests r0 JOIN public.kd_profiles u ON u.user_id=r0.owner_id
      WHERE NOT r0.cancelled AND u.verified_at IS NOT NULL AND NOT u.disabled
      AND (q='' OR strpos(lower(concat_ws(' ',r0.title,u.organization,u.city,r0.subject,r0.board)),lower(q))>0)
      AND (COALESCE(p_data->>'subject','')='' OR r0.subject=p_data->>'subject')
      AND (COALESCE(p_data->>'grade','')='' OR r0.grade=p_data->>'grade')
      AND (COALESCE(p_data->>'language','')='' OR r0.language=p_data->>'language')
      AND (COALESCE(p_data->>'urgency','')='' OR r0.urgency=p_data->>'urgency')
      AND (COALESCE(p_data->>'needs','true')<>'true' OR r0.quantity>COALESCE((SELECT sum(quantity) FROM public.kd_pledges WHERE request_id=r0.id AND NOT cancelled),0))
    ) SELECT jsonb_build_object('total',(SELECT count(*) FROM matches),'page',page_no,
      'items',COALESCE((SELECT jsonb_agg(public.kd_public_request(id) ORDER BY created_at DESC,id) FROM
        (SELECT * FROM matches ORDER BY created_at DESC,id LIMIT page_size OFFSET page_no*page_size) x),'[]'::jsonb)) INTO result;
    RETURN result;
  END IF;

  -- JWT presence alone is insufficient: reject retired/banned/unconfirmed users.
  IF uid IS NULL OR NOT EXISTS(SELECT 1 FROM auth.users u WHERE u.id=uid AND u.email_confirmed_at IS NOT NULL
      AND (u.banned_until IS NULL OR u.banned_until<=now()) AND lower(u.email) NOT IN ('school@demo.pk','ngo@demo.pk')) THEN
    RAISE EXCEPTION 'Sign in with a confirmed, active account' USING ERRCODE='42501'; END IF;
  SELECT * INTO actor FROM public.kd_profiles WHERE user_id=uid;
  SELECT EXISTS(SELECT 1 FROM public.kd_admins WHERE user_id=uid) INTO is_admin;
  IF actor.disabled THEN RAISE EXCEPTION 'Account suspended. Contact the project administrator' USING ERRCODE='42501'; END IF;
  IF p_action='me' THEN RETURN jsonb_build_object('profile',CASE WHEN actor.user_id IS NULL THEN NULL ELSE to_jsonb(actor) END,'is_admin',is_admin); END IF;
  IF p_action='profile' THEN
    IF actor.user_id IS NULL THEN
      IF p_data->>'role' NOT IN ('school','ngo') OR p_data->>'role' IS NULL THEN RAISE EXCEPTION 'Choose school or donor'; END IF;
      INSERT INTO public.kd_profiles(user_id,role,organization,person,phone,city)
      VALUES(uid,p_data->>'role',trim(p_data->>'organization'),trim(p_data->>'person'),p_data->>'phone',trim(p_data->>'city')) RETURNING * INTO actor;
    ELSE
      -- Organization identity/role cannot be changed by editing user metadata.
      UPDATE public.kd_profiles SET person=trim(p_data->>'person'),phone=p_data->>'phone',city=trim(p_data->>'city')
      WHERE user_id=uid RETURNING * INTO actor;
    END IF;
    RETURN to_jsonb(actor);
  END IF;
  IF actor.user_id IS NULL AND p_action NOT IN ('admin_queue','admin_review','admin_resolve','admin_transfer') THEN RAISE EXCEPTION 'Complete your organization profile first'; END IF;

  IF p_action='workspace' THEN
    page_no := greatest(0,least(10000,COALESCE((p_data->>'page')::integer,0)));
    SELECT COALESCE(jsonb_agg(public.kd_public_request(x.id) || jsonb_build_object('address',x.address,'owner_id',x.owner_id) ORDER BY x.created_at DESC,x.id),'[]'::jsonb)
    INTO items FROM (SELECT * FROM public.kd_requests WHERE owner_id=uid ORDER BY created_at DESC,id LIMIT 12 OFFSET page_no*12) x;
    result := jsonb_build_object('requests',items,'request_total',(SELECT count(*) FROM public.kd_requests WHERE owner_id=uid));
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC,x.id),'[]'::jsonb) INTO items FROM (
      SELECT p0.*,public.kd_public_request(r0.id) AS request,
        jsonb_build_object('organization',d.organization,'person',d.person,'phone',d.phone,'city',d.city) AS donor,
        jsonb_build_object('organization',u.organization,'person',u.person,'phone',u.phone,'address',r0.address,'city',u.city) AS school,
        COALESCE((SELECT jsonb_agg(to_jsonb(s0) ORDER BY s0.dispatched_at) FROM public.kd_shipments s0 WHERE s0.pledge_id=p0.id),'[]'::jsonb) AS shipments
      FROM public.kd_pledges p0 JOIN public.kd_requests r0 ON r0.id=p0.request_id JOIN public.kd_profiles d ON d.user_id=p0.donor_id
      JOIN public.kd_profiles u ON u.user_id=r0.owner_id WHERE p0.donor_id=uid OR r0.owner_id=uid
      ORDER BY p0.created_at DESC,p0.id LIMIT 12 OFFSET page_no*12) x;
    result := result || jsonb_build_object('pledges',items,'pledge_total',(SELECT count(*) FROM public.kd_pledges p0 JOIN public.kd_requests r0 ON r0.id=p0.request_id WHERE p0.donor_id=uid OR r0.owner_id=uid),
      'events',COALESCE((SELECT jsonb_agg(to_jsonb(e)) FROM (SELECT id,message,request_id,created_at FROM public.kd_events WHERE recipient_id=uid ORDER BY created_at DESC LIMIT 30) e),'[]'::jsonb),
      'issues',COALESCE((SELECT jsonb_agg(to_jsonb(i)) FROM (SELECT * FROM public.kd_issues WHERE user_id=uid ORDER BY created_at DESC LIMIT 30) i),'[]'::jsonb));
    RETURN result;
  END IF;
  IF p_action='issue' THEN
    PERFORM 1 FROM public.kd_profiles WHERE user_id=uid FOR UPDATE;
    IF (SELECT count(*) FROM public.kd_issues WHERE user_id=uid AND created_at>now()-interval '1 day')>=10 THEN RAISE EXCEPTION 'Daily report limit reached'; END IF;
    INSERT INTO public.kd_issues(user_id,request_id,message) VALUES(uid,NULLIF(p_data->>'request_id','')::uuid,trim(p_data->>'message'));
    RETURN jsonb_build_object('ok',true);
  END IF;
  IF p_action IN ('admin_queue','admin_review','admin_resolve','admin_transfer') THEN
    IF NOT is_admin THEN RAISE EXCEPTION 'Administrator access required' USING ERRCODE='42501'; END IF;
    IF p_action='admin_transfer' THEN
      -- All transfers serialize; recheck authority after waiting on the lock.
      PERFORM pg_catalog.pg_advisory_xact_lock(762013,1);
      IF NOT EXISTS(SELECT 1 FROM public.kd_admins WHERE user_id=uid) THEN RAISE EXCEPTION 'Administrator access changed'; END IF;
      SELECT u.id INTO ident FROM auth.users u WHERE lower(u.email)=lower(trim(p_data->>'email'))
        AND u.email_confirmed_at IS NOT NULL AND (u.banned_until IS NULL OR u.banned_until<=now())
        AND lower(u.email) NOT IN ('school@demo.pk','ngo@demo.pk')
        AND NOT EXISTS(SELECT 1 FROM public.kd_profiles p0 WHERE p0.user_id=u.id AND p0.disabled);
      IF ident IS NULL OR ident=uid THEN RAISE EXCEPTION 'Choose a different confirmed, active website account'; END IF;
      INSERT INTO public.kd_admins(user_id) VALUES(ident) ON CONFLICT DO NOTHING;
      DELETE FROM public.kd_admins WHERE user_id=uid;
      INSERT INTO public.kd_events(actor_id,recipient_id,message) VALUES(uid,ident,'Administrator role transferred to this account.');
      RETURN jsonb_build_object('ok',true);
    END IF;
    IF p_action='admin_queue' THEN
      RETURN jsonb_build_object('profiles',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT * FROM public.kd_profiles WHERE role<>'admin' ORDER BY verified_at NULLS FIRST,created_at DESC LIMIT 100) x),'[]'::jsonb),
        'issues',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT * FROM public.kd_issues WHERE NOT resolved ORDER BY created_at LIMIT 100) x),'[]'::jsonb));
    ELSIF p_action='admin_review' THEN
      IF COALESCE(p_data->>'decision','') NOT IN ('approve','reject','suspend') THEN RAISE EXCEPTION 'Choose approve, reject or suspend'; END IF;
      IF length(trim(COALESCE(p_data->>'note','')))<10 THEN RAISE EXCEPTION 'Record the verification evidence or reason'; END IF;
      UPDATE public.kd_profiles SET verified_at=CASE WHEN p_data->>'decision'='approve' THEN now() END,
        verified_by=uid,review_note=left(p_data->>'note',1000),disabled=(p_data->>'decision'='suspend')
      WHERE user_id=(p_data->>'user_id')::uuid AND role<>'admin';
      IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found'; END IF;
      INSERT INTO public.kd_events(actor_id,recipient_id,message) VALUES(uid,(p_data->>'user_id')::uuid,'Organization review: '||(p_data->>'decision'));
    ELSE
      IF length(trim(COALESCE(p_data->>'response','')))<10 THEN RAISE EXCEPTION 'Enter a resolution of at least 10 characters'; END IF;
      UPDATE public.kd_issues SET resolved=true,response=left(p_data->>'response',2000) WHERE id=(p_data->>'id')::uuid;
      IF NOT FOUND THEN RAISE EXCEPTION 'Report not found'; END IF;
    END IF;
    RETURN jsonb_build_object('ok',true);
  END IF;

  -- Every remaining operation is an authenticated, transactional write.
  IF p_action IN ('request_save','request_cancel') THEN
    IF actor.role<>'school' THEN RAISE EXCEPTION 'School account required' USING ERRCODE='42501'; END IF;
    ident := (p_data->>'id')::uuid;
    IF ident IS NULL THEN RAISE EXCEPTION 'Submission identifier is required'; END IF;
    -- Serialize colliding IDs across accounts before checking ownership.
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(ident::text,0));
    -- Serialize idempotent creates for this account, including daily rate checks.
    PERFORM 1 FROM public.kd_profiles WHERE user_id=uid FOR UPDATE;
    SELECT * INTO r FROM public.kd_requests WHERE id=ident FOR UPDATE;
    IF r.id IS NOT NULL THEN
      IF r.owner_id<>uid THEN RAISE EXCEPTION 'Not your request' USING ERRCODE='42501'; END IF;
      IF p_data->>'retry_create'='true' THEN RETURN public.kd_public_request(r.id); END IF;
      IF r.version<>COALESCE((p_data->>'version')::integer,0) THEN RAISE EXCEPTION 'Request changed. Refresh before editing'; END IF;
      IF EXISTS(SELECT 1 FROM public.kd_pledges WHERE request_id=r.id AND NOT cancelled) THEN RAISE EXCEPTION 'Active pledges exist. Resolve them before editing or cancelling'; END IF;
      IF p_action='request_cancel' THEN
        UPDATE public.kd_requests SET cancelled=true,version=version+1 WHERE id=r.id;
        RETURN jsonb_build_object('ok',true);
      END IF;
    ELSE
      IF p_action='request_cancel' THEN RAISE EXCEPTION 'Request not found'; END IF;
      IF (SELECT count(*) FROM public.kd_requests WHERE owner_id=uid AND created_at>now()-interval '1 day')>=20 THEN RAISE EXCEPTION 'Daily request limit reached'; END IF;
    END IF;
    IF (p_data->>'needed_by')::date<current_date THEN RAISE EXCEPTION 'Choose today or a future needed-by date'; END IF;
    INSERT INTO public.kd_requests(id,owner_id,title,description,subject,grade,board,language,edition,condition,needed_by,quantity,urgency,address,emis)
    VALUES(ident,uid,trim(p_data->>'title'),trim(p_data->>'description'),p_data->>'subject',p_data->>'grade',trim(p_data->>'board'),p_data->>'language',trim(p_data->>'edition'),p_data->>'condition',(p_data->>'needed_by')::date,(p_data->>'quantity')::integer,p_data->>'urgency',trim(p_data->>'address'),COALESCE(p_data->>'emis',''))
    ON CONFLICT(id) DO UPDATE SET title=EXCLUDED.title,description=EXCLUDED.description,subject=EXCLUDED.subject,grade=EXCLUDED.grade,
      board=EXCLUDED.board,language=EXCLUDED.language,edition=EXCLUDED.edition,condition=EXCLUDED.condition,needed_by=EXCLUDED.needed_by,
      quantity=EXCLUDED.quantity,urgency=EXCLUDED.urgency,address=EXCLUDED.address,emis=EXCLUDED.emis,version=kd_requests.version+1;
    RETURN public.kd_public_request(ident);
  END IF;

  IF p_action='pledge' THEN
    IF actor.role<>'ngo' OR actor.verified_at IS NULL THEN RAISE EXCEPTION 'An approved donor account is required' USING ERRCODE='42501'; END IF;
    ident := (p_data->>'id')::uuid; rid := (p_data->>'request_id')::uuid; n := (p_data->>'quantity')::integer;
    PERFORM 1 FROM public.kd_profiles WHERE user_id=uid FOR UPDATE;
    SELECT * INTO r FROM public.kd_requests WHERE id=rid FOR UPDATE;
    IF r.id IS NULL OR r.cancelled THEN RAISE EXCEPTION 'Request unavailable'; END IF;
    SELECT * INTO p FROM public.kd_pledges WHERE id=ident;
    IF p.id IS NOT NULL THEN
      IF p.donor_id<>uid OR p.request_id<>rid OR p.quantity<>n THEN RAISE EXCEPTION 'Submission identifier already used'; END IF;
      RETURN to_jsonb(p);
    END IF;
    IF NOT EXISTS(SELECT 1 FROM public.kd_profiles WHERE user_id=r.owner_id AND verified_at IS NOT NULL AND NOT disabled) THEN RAISE EXCEPTION 'School is awaiting review'; END IF;
    SELECT COALESCE(sum(quantity),0) INTO used FROM public.kd_pledges WHERE request_id=rid AND NOT cancelled;
    IF n IS NULL OR n<1 OR n>r.quantity-used THEN RAISE EXCEPTION 'Available quantity changed. Refresh and choose up to % books',r.quantity-used; END IF;
    IF (SELECT count(*) FROM public.kd_pledges WHERE donor_id=uid AND created_at>now()-interval '1 day')>=50 THEN RAISE EXCEPTION 'Daily pledge limit reached'; END IF;
    INSERT INTO public.kd_pledges(id,request_id,donor_id,quantity,note) VALUES(ident,rid,uid,n,left(COALESCE(p_data->>'note',''),1000)) RETURNING * INTO p;
    INSERT INTO public.kd_events(actor_id,recipient_id,request_id,message) VALUES(uid,r.owner_id,r.id,actor.organization||' pledged '||n||' books.');
    RETURN to_jsonb(p);
  END IF;
  IF p_action IN ('pledge_edit','pledge_cancel','dispatch','receive') THEN
    IF p_action='receive' THEN
      SELECT * INTO s FROM public.kd_shipments WHERE id=(p_data->>'id')::uuid;
      SELECT * INTO p FROM public.kd_pledges WHERE id=s.pledge_id;
    ELSE SELECT * INTO p FROM public.kd_pledges WHERE id=(p_data->>'pledge_id')::uuid; END IF;
    IF p.id IS NULL THEN RAISE EXCEPTION 'Pledge not found'; END IF;
    -- Consistent lock order for reservation, cancellation, shipment and receipt.
    SELECT * INTO r FROM public.kd_requests WHERE id=p.request_id FOR UPDATE;
    SELECT * INTO p FROM public.kd_pledges WHERE id=p.id FOR UPDATE;
    IF p_action='receive' THEN
      IF r.owner_id<>uid OR actor.role<>'school' THEN RAISE EXCEPTION 'Only the receiving school may confirm this parcel' USING ERRCODE='42501'; END IF;
      SELECT * INTO s FROM public.kd_shipments WHERE id=s.id FOR UPDATE;
      n := (p_data->>'received_quantity')::integer;
      IF n IS NULL OR n<s.received_quantity OR n>s.quantity THEN RAISE EXCEPTION 'Received total must be between % and %',s.received_quantity,s.quantity; END IF;
      IF s.version<>COALESCE((p_data->>'version')::integer,0) THEN
        IF n=s.received_quantity AND COALESCE(p_data->>'note','')=s.receipt_note AND COALESCE((p_data->>'issue')::boolean,false)=s.issue THEN RETURN to_jsonb(s); END IF;
        RAISE EXCEPTION 'Receipt changed. Refresh before confirming';
      END IF;
      IF COALESCE((p_data->>'issue')::boolean,false) AND length(trim(COALESCE(p_data->>'note','')))<10 THEN RAISE EXCEPTION 'Describe the missing or damaged books'; END IF;
      UPDATE public.kd_shipments SET received_quantity=n,receipt_note=COALESCE(p_data->>'note',''),issue=COALESCE((p_data->>'issue')::boolean,false),version=version+1,
        received_at=CASE WHEN n=quantity THEN now() ELSE received_at END WHERE id=s.id RETURNING * INTO s;
      INSERT INTO public.kd_events(actor_id,recipient_id,request_id,message) VALUES(uid,p.donor_id,r.id,'School recorded '||n||' of '||s.quantity||' books received.');
      RETURN to_jsonb(s);
    END IF;
    IF p.donor_id<>uid OR actor.role<>'ngo' THEN RAISE EXCEPTION 'Not your pledge' USING ERRCODE='42501'; END IF;
    IF p.cancelled THEN RAISE EXCEPTION 'Pledge is cancelled'; END IF;
    SELECT COALESCE(sum(quantity),0) INTO used FROM public.kd_shipments WHERE pledge_id=p.id;
    IF p_action='dispatch' THEN
      IF actor.verified_at IS NULL OR r.cancelled THEN RAISE EXCEPTION 'Dispatch is unavailable'; END IF;
      ident := (p_data->>'id')::uuid; n := (p_data->>'quantity')::integer;
      SELECT * INTO s FROM public.kd_shipments WHERE id=ident;
      IF s.id IS NOT NULL THEN
        IF s.pledge_id<>p.id OR s.quantity<>n THEN RAISE EXCEPTION 'Submission identifier already used'; END IF;
        RETURN to_jsonb(s);
      END IF;
      IF n IS NULL OR n<1 OR n>p.quantity-used THEN RAISE EXCEPTION 'Parcel quantity exceeds undispatched pledge'; END IF;
      SELECT * INTO school FROM public.kd_profiles WHERE user_id=r.owner_id;
      IF school.disabled OR school.verified_at IS NULL THEN RAISE EXCEPTION 'School approval is no longer active. Contact the administrator'; END IF;
      INSERT INTO public.kd_shipments(id,pledge_id,quantity,carrier,tracking,sender_name,sender_person,sender_phone,sender_city,receiver_name,receiver_person,receiver_phone,receiver_address)
      VALUES(ident,p.id,n,trim(p_data->>'carrier'),trim(p_data->>'tracking'),actor.organization,actor.person,actor.phone,actor.city,school.organization,school.person,school.phone,r.address) RETURNING * INTO s;
      INSERT INTO public.kd_events(actor_id,recipient_id,request_id,message) VALUES(uid,r.owner_id,r.id,actor.organization||' dispatched a parcel of '||n||' books.');
      RETURN to_jsonb(s);
    END IF;
    IF p.version<>COALESCE((p_data->>'version')::integer,0) THEN RAISE EXCEPTION 'Pledge changed. Refresh before editing'; END IF;
    IF p_action='pledge_cancel' THEN
      IF used>0 THEN RAISE EXCEPTION 'A dispatched pledge cannot be cancelled. Report an issue instead'; END IF;
      UPDATE public.kd_pledges SET cancelled=true,version=version+1 WHERE id=p.id RETURNING * INTO p;
    ELSE
      n := (p_data->>'quantity')::integer;
      IF n IS NULL OR n<greatest(1,used) OR n>r.quantity-COALESCE((SELECT sum(quantity) FROM public.kd_pledges WHERE request_id=r.id AND id<>p.id AND NOT cancelled),0) THEN RAISE EXCEPTION 'Quantity conflicts with shipments or remaining need'; END IF;
      UPDATE public.kd_pledges SET quantity=n,note=left(COALESCE(p_data->>'note',''),1000),version=version+1 WHERE id=p.id RETURNING * INTO p;
    END IF;
    INSERT INTO public.kd_events(actor_id,recipient_id,request_id,message) VALUES(uid,r.owner_id,r.id,actor.organization||' updated their pledge.');
    RETURN to_jsonb(p);
  END IF;
  RAISE EXCEPTION 'Unknown operation';
END $fn$;
REVOKE ALL ON FUNCTION public.kd_api(text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.kd_api(text,jsonb) TO anon,authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
