-- Haven Retreats fictional demo KB. Run once in the intended Supabase demo project.
-- No embeddings or extension required. Stops if this dedicated table already exists.
-- Does not replace existing KB data or enable public access.
BEGIN;
CREATE TABLE public.haven_demo_kb (
  slug text PRIMARY KEY,
  topic text NOT NULL,
  content text NOT NULL,
  source text NOT NULL,
  version text NOT NULL,
  content_type text NOT NULL CHECK (content_type = 'fictional_demo'),
  enabled_for_demo boolean NOT NULL DEFAULT false,
  search_vector tsvector GENERATED ALWAYS AS (
    setweight(to_tsvector('english'::regconfig, topic), 'A') ||
    setweight(to_tsvector('english'::regconfig, content), 'B')
  ) STORED
);
CREATE INDEX haven_demo_kb_search_idx ON public.haven_demo_kb USING gin(search_vector);
ALTER TABLE public.haven_demo_kb ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.haven_demo_kb FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.haven_demo_kb TO service_role;
INSERT INTO public.haven_demo_kb
(slug, topic, content, source, version, content_type, enabled_for_demo) VALUES
('business-overview', 'Business overview', 'Haven Retreats is a fictional business used in an AI receptionist demonstration. The receptionist helps with retreat inquiries, consultation scheduling requests, general questions and requests for a human analyst. This sample does not establish a real venue, address, retreat inventory or operating business.', 'haven-demo-v1', '1.0', 'fictional_demo', true),
('consultation-hours', 'Consultation hours and timezone', 'Haven Retreats demo consultation appointments are offered Monday through Friday, 9:00 AM to 5:00 PM, Asia/Manila time. These are consultation scheduling hours, not a promise of live human support hours. The receptionist must use the calendar to check actual available slots and must explain the timezone when offering an appointment.', 'haven-demo-v1', '1.0', 'fictional_demo', true),
('consultation-duration', 'Consultation duration and buffer', 'A Haven Retreats demo consultation lasts 30 minutes. The scheduling design includes a 15-minute buffer. Buffer placement before or after the appointment has not been finalized, so the receptionist must not calculate available slots from the buffer rule alone. Actual slots must come from the calendar. Calendar setup and synchronization are not established by this knowledge base.', 'haven-demo-v1', '1.0', 'fictional_demo', true),
('consultation-reservation', 'What consultation booking reserves', 'For this fictional sample, a confirmed consultation reserves consultation time only. It does not reserve retreat accommodation, a retreat place, travel, admission or payment arrangements. The receptionist must not claim that a retreat reservation or purchase is confirmed because a consultation was booked. An analyst must verify any separate retreat reservation request.', 'haven-demo-v1', '1.0', 'fictional_demo', true),
('cancellation-rescheduling', 'Consultation cancellation and rescheduling', 'For the Haven Retreats demo, consultation cancellation or rescheduling is allowed at least 24 hours before the consultation start time. Requests inside the 24-hour window require human analyst review; the receptionist must not invent an exception or a penalty. This rule applies to consultations only. Retreat cancellation fees, refunds and payment policies have not been supplied and require an analyst.', 'haven-demo-v1', '1.0', 'fictional_demo', true),
('pricing-packages', 'Retreat prices and packages', 'The Haven Retreats demo knowledge base does not contain approved retreat prices, discounts, package inclusions, dates, overnight stay details or payment instructions. The receptionist may offer to pass these questions to a human analyst. It must not invent a price, guarantee a discount, provide bank details or describe an unverified retreat package.', 'haven-demo-v1', '1.0', 'fictional_demo', true),
('live-booking-status', 'Live availability and booking confirmation', 'A static knowledge base cannot establish live appointment availability or a customer''s booking status. The receptionist may say a consultation is confirmed only after the booking system returns a verified successful appointment result and appointment identifier. A requested slot, a conversation summary or a timed-out booking request is not proof of confirmation. An uncertain result stays pending for verification; do not create a second booking merely because the first response was delayed.', 'haven-demo-v1', '1.0', 'fictional_demo', true),
('human-handoff', 'When to transfer to a human analyst', 'The Haven Retreats demo receptionist should request human analyst help when the customer asks for a person, the KB lacks the answer, sources conflict, the request is unclear after clarification, or an action cannot be verified. Explain that human help is needed for an accurate answer. Transfer the call only through the configured transfer tool. Saying that a transfer was requested does not mean an analyst answered. For this demo, Vergel is the designated case owner.', 'haven-demo-v1', '1.0', 'fictional_demo', true),
('analyst-unavailable', 'Analyst busy, no answer or disconnected transfer', 'If the Haven Retreats demo analyst is busy, does not answer or the transfer disconnects, do not report a successful human handoff. Explain that the connection was not completed and ask permission to request a callback. Keep the inquiry unresolved with its owner, a short summary, the failure reason and the next action. The internal demo targets are acknowledgment within one business hour and unresolved-case review within one business day. These are internal targets, not a guaranteed callback time; business-hour timers are not defined by this KB.', 'haven-demo-v1', '1.0', 'fictional_demo', true),
('outbound-callback-policy', 'Callback permission, calling window and retry limit', 'A Haven Retreats demo callback requires permission for the intended callback purpose. Do not call a customer who has opted out, has Call DND enabled, or whose inquiry is on human-takeover hold. Call only on weekdays between 9:00 AM and 5:00 PM in the customer''s verified timezone. Allow at most two attempts per inquiry, at least 24 hours apart. Unknown timezone, calling country, required disclosure or permission means hold for review. These rules must be checked by automation immediately before dialing; retrieving this text does not authorize a call.', 'haven-demo-v1', '1.0', 'fictional_demo', true),
('unknown-answer-provider-failure', 'Missing knowledge versus AI provider failure', 'If the Haven Retreats demo KB does not support an answer, the receptionist should say it cannot verify that detail, ask a useful clarification when appropriate, or offer human analyst help. Switching models does not supply missing business facts. A technical AI provider failure may use the configured backup provider, but the backup must use the same supported KB evidence. If both providers fail, the automation should use a non-model failure message and the human handoff route. No fallback is operational merely because this policy is stored in the KB.', 'haven-demo-v1', '1.0', 'fictional_demo', true),
('privacy-scope', 'Privacy and sensitive requests', 'For the Haven Retreats demo, collect only the name, callback number and inquiry details needed for the requested assistance, subject to the configured form and permission rules. Do not ask callers to speak passwords, one-time codes, full payment-card details or sensitive medical histories. Do not disclose another customer''s details. Questions about health suitability, legal terms, payment disputes or personal records require an appropriate human review; the receptionist must not make a professional determination from this sample KB.', 'haven-demo-v1', '1.0', 'fictional_demo', true)
;
CREATE FUNCTION public.search_haven_demo_kb(p_query text, p_limit integer DEFAULT 3)
RETURNS TABLE(slug text, topic text, content text, source text, version text, rank real)
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_query tsquery;
BEGIN
  IF p_query IS NULL OR btrim(p_query) = '' THEN RETURN; END IF;
  v_query := plainto_tsquery('english'::regconfig, left(p_query, 2000));
  IF numnode(v_query) = 0 THEN RETURN; END IF;
  -- Match any meaningful query word. Agent must check direct answer support.
  v_query := replace(v_query::text, ' & ', ' | ')::tsquery;
  RETURN QUERY
    SELECT d.slug, d.topic, d.content, d.source, d.version,
           ts_rank_cd(d.search_vector, v_query) AS rank
    FROM public.haven_demo_kb AS d
    WHERE d.enabled_for_demo AND d.content_type = 'fictional_demo'
      AND d.search_vector @@ v_query
    ORDER BY ts_rank_cd(d.search_vector, v_query) DESC, d.slug
    LIMIT greatest(1, least(coalesce(p_limit, 3), 5));
END;
$function$;
REVOKE ALL ON FUNCTION public.search_haven_demo_kb(text, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.search_haven_demo_kb(text, integer) TO service_role;
COMMIT;

-- Check count after successful import: expected 12.
SELECT count(*) AS demo_passages FROM public.haven_demo_kb;
-- Run separately to try retrieval:
-- SELECT * FROM public.search_haven_demo_kb('consultation duration', 3);
-- SELECT * FROM public.search_haven_demo_kb('quantum satellite propulsion', 3);
