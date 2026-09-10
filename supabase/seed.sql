insert into public.company_domains (domain, company_name, industry, status)
values
  ('orbitsystems.com', 'Orbit Systems', 'Software infrastructure', 'approved'),
  ('northstar.ai', 'Northstar AI', 'Artificial intelligence', 'approved'),
  ('harbourlabs.com', 'Harbour Labs', 'Developer tools', 'approved'),
  ('shopify.com', 'Shopify', 'Commerce technology', 'approved'),
  ('meta.com', 'Meta', 'Consumer technology', 'approved'),
  ('newventurelabs.ca', 'New Venture Labs', 'Technology', 'review_pending')
on conflict (domain) do update set
  company_name = excluded.company_name,
  industry = excluded.industry,
  status = excluded.status;

