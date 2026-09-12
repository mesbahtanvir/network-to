# Data Model: Verified Company Marks

Entities from the spec mapped to Postgres, Storage, and the iOS client. Validation rules are
quoted from the requirements they implement; constraints below are the ones the migrations
enforce.

## Postgres

### `public.companies` (new)

One row per verified company (spec entity "Verified company").

| Column | Type | Constraint | Notes |
|--------|------|------------|-------|
| `key` | text | primary key, `key ~ '^[a-z0-9][a-z0-9-]{0,62}$'` | stable slug used in storage paths and the client reference; never an email domain (FR-013) |
| `name` | text | not null, 1–120 chars | display name copied to `profiles.company_name` at sign-up (unchanged behaviour) |
| `industry` | text | not null, 1–120 chars | copied to `profiles.industry` at sign-up |
| `website_url` | text | null or `^https://` and ≤ 200 chars | where the operations action fetches the icon (FR-022); defaults to the primary domain |
| `coverage_clause` | text | not null, in (`a`, `b`, `c`, `launch`) | FR-018; `launch` is closed to new companies |
| `status` | text | not null, default `approved`, in (`approved`, `review_pending`, `rejected`) | marks are shown only when `approved` (FR-028) |
| `mark_status` | text | not null, default `not_yet_fetched`, in (`not_yet_fetched`, `available`, `no_icon_published`, `fetch_failed`, `withheld`) | FR-018 |
| `mark_version` | integer | not null, default 0, ≥ 0 | incremented on every successful fetch (FR-015) |
| `mark_path` | text | null or `^[a-z0-9][a-z0-9-]{0,62}/[0-9]+\.(png|jpg)$` | current served object path; null unless `available` |
| `mark_content_type` | text | null or in (`image/png`, `image/jpeg`) | |
| `mark_fetched_at` | timestamptz | | last successful fetch |
| `mark_source_url` | text | ≤ 500 chars | where the served icon came from |
| `mark_failure_reason` | text | ≤ 300 chars | reason of the last `no_icon_published` or `fetch_failed` outcome |
| `mark_refresh_requested` | boolean | not null default false | set by `request_company_mark_refresh` (FR-020) |
| `mark_claimed_at` | timestamptz | | set by `claim_company_mark_targets`; a claim younger than 15 minutes is not re-issued |
| `created_at`, `updated_at` | timestamptz | not null default now() | `updated_at` touched by trigger |

RLS enabled; all privileges revoked from `anon` and `authenticated`; no policies. Only
`security definer` functions read it on behalf of members.

State transitions of `mark_status`:

- `not_yet_fetched` → `available` (outcome `fetched`), `no_icon_published`, or `fetch_failed`
- `fetch_failed` → any (retried by the next populate run)
- `no_icon_published` → any (retried only when `mark_refresh_requested`)
- `available` → `available` with `mark_version + 1` (refresh), `withheld` (operator), or stays
  `available` with `mark_failure_reason` set when a requested refresh fails (the old version keeps
  serving)
- `withheld` → `available` when the operator lifts the withholding (`set_company_mark_withheld(key, false)`
  restores the current version if one exists, otherwise `not_yet_fetched`)

### `public.company_domains` (reshaped)

| Column | Change |
|--------|--------|
| `company_key` | new, `references public.companies(key)`, backfilled for every existing row, then `not null` |
| `status` | unchanged: still gates sign-up (FR-019) |
| `company_name`, `industry` | unchanged and kept in sync from `companies` by a trigger so the sign-up trigger and `validate_company_domain` behave exactly as today |

### `private.company_mark_versions` (new)

Spec entity "Company mark" history; only the row whose `state = 'served'` is referenced from
`companies.mark_path`.

| Column | Type | Constraint |
|--------|------|------------|
| `company_key` | text | references `public.companies(key)` on delete cascade |
| `version` | integer | ≥ 1; primary key (`company_key`, `version`) |
| `path` | text | same regex as `companies.mark_path` |
| `content_type` | text | in (`image/png`, `image/jpeg`) |
| `byte_size` | integer | 1 … 1,048,576 (FR-025) |
| `width`, `height` | integer | ≥ 128 (FR-025) |
| `source_url` | text | ≤ 500 chars |
| `fetched_at` | timestamptz | not null default now() |
| `state` | text | in (`served`, `superseded`, `withheld`, `withdrawn`) |
| `retired_at` | timestamptz | set when `state` leaves `served`; the file is purged 30 days later (FR-027) |

Revoked from every client role.

### `private.company_mark_runs` and `private.company_mark_run_items` (new)

Spec entity "Mark operations run".

`company_mark_runs`: `id uuid pk`, `started_at`, `finished_at`, `requested_by text ≤ 120`,
`scope jsonb` (`{"action":"populate"|"refresh"|"purge","companies":[...]}`), `status` in
(`running`, `completed`, `failed`, `skipped`), `invocations integer ≥ 0`, `summary jsonb`,
`error_message text ≤ 1000`. Only one row may be `running` at a time (partial unique index).

`company_mark_run_items`: `run_id uuid references company_mark_runs on delete cascade`,
`company_key text`, `outcome` in (`fetched`, `no_icon_published`, `fetch_failed`, `skipped_existing`),
`detail text ≤ 300`, `recorded_at`; primary key (`run_id`, `company_key`).

Retention: runs (and their items by cascade) older than 180 days are deleted by
`run_retention_maintenance()`.

## Storage

Bucket `company-marks`: `public = true`, `file_size_limit = 1048576`,
`allowed_mime_types = {image/png, image/jpeg}`. Object path `<key>/<version>.<png|jpg>`.
No `storage.objects` policy exists for `anon` or `authenticated`, so listing returns nothing;
public object reads need no policy. Objects are written and deleted only by the Edge Function
with the service role.

## Read-model reference (client contract)

`company_mark` appears next to `company_name` in `private.public_profile(...)`, in the person
object of `get_current_introduction()`, and in `get_own_company_mark()`:

```json
{ "key": "shopify", "version": 2, "path": "shopify/2.png" }
```

It is `null` unless the member's domain maps to a company whose `status = 'approved'` and
`mark_status = 'available'` (FR-028, FR-021, FR-026).

## iOS

- `CompanyMarkReference: Codable, Hashable, Sendable` with `key`, `version`, `path`.
- `ProfessionalProfile.companyMark: CompanyMarkReference?` (default `nil`; appended at the end
  of the struct so existing memberwise calls compile).
- `CompanyMonogram.characters(for:)` implements FR-004 (pure function, unit-tested).
- `AppStore.companyMarks: [CompanyMarkReference: Data]` (published, `private(set)`) plus
  `companyMarkData(for:)`, `ensureCompanyMark(_:)`, and `clearCompanyMarks()`.
- `CompanyMarkDiskCache` (Services): `Caches/CompanyMarks/<key>-<version>`.

## Registry (this migration)

130 clause a, 101 clause b, 12 clause c, 6 launch carry-overs; 249 companies,
258 domains. Clause meanings: (a) constituent of the Nasdaq-100, S&P 500, or S&P/TSX
Composite, or a wholly owned subsidiary of one, whose primary business is technology; (b) privately
held North American technology company with at least 1,000 employees; (c) technology employer with at
least 200 engineering staff in Toronto; (launch) initial registry entry that meets none of the three
today (Twilio, Figma, Dropbox, Lyft, Pinterest, Snap).

| Key | Company | Industry | Clause | Domains |
|-----|---------|----------|--------|---------|
| `1password` | 1Password | Security technology | b | `1password.com` |
| `activision-blizzard` | Activision Blizzard | Gaming technology | a | `activision.com`, `blizzard.com` |
| `adobe` | Adobe | Creative and document technology | a | `adobe.com` |
| `adp` | ADP | HR technology | a | `adp.com` |
| `affirm` | Affirm | Financial technology | c | `affirm.com` |
| `airbnb` | Airbnb | Travel technology | a | `airbnb.com` |
| `akamai` | Akamai | Internet infrastructure | a | `akamai.com` |
| `alteryx` | Alteryx | Analytics software | b | `alteryx.com` |
| `amazon` | Amazon | Commerce and cloud technology | a | `amazon.com` |
| `amd` | AMD | Semiconductor technology | a | `amd.com` |
| `analog-devices` | Analog Devices | Semiconductor technology | a | `analog.com` |
| `anaplan` | Anaplan | Planning software | b | `anaplan.com` |
| `anduril` | Anduril | Defense technology | b | `anduril.com` |
| `ansys` | Ansys | Simulation software | a | `ansys.com` |
| `anthropic` | Anthropic | Artificial intelligence | b | `anthropic.com` |
| `apple` | Apple | Consumer technology and platforms | a | `apple.com` |
| `applied-intuition` | Applied Intuition | Mobility technology | b | `appliedintuition.com` |
| `applied-materials` | Applied Materials | Semiconductor equipment | a | `amat.com` |
| `applovin` | AppLovin | Mobile advertising technology | a | `applovin.com` |
| `arctic-wolf` | Arctic Wolf | Security technology | b | `arcticwolf.com` |
| `arista` | Arista | Networking technology | a | `arista.com` |
| `assent` | Assent | Supply chain compliance software | b | `assent.com` |
| `athenahealth` | athenahealth | Health technology | b | `athenahealth.com` |
| `atlassian` | Atlassian | Developer and collaboration tools | a | `atlassian.com` |
| `autodesk` | Autodesk | Design software | a | `autodesk.com` |
| `automation-anywhere` | Automation Anywhere | Automation software | b | `automationanywhere.com` |
| `automattic` | Automattic | Web publishing technology | b | `automattic.com` |
| `avalara` | Avalara | Tax technology | b | `avalara.com` |
| `axon` | Axon | Public safety technology | a | `axon.com` |
| `bamboohr` | BambooHR | HR technology | b | `bamboohr.com` |
| `barracuda` | Barracuda Networks | Security technology | b | `barracuda.com` |
| `behaviour-interactive` | Behaviour Interactive | Gaming technology | b | `bhvr.com` |
| `blackberry` | BlackBerry | Security and IoT software | a | `blackberry.com` |
| `block` | Block | Financial technology | a | `block.xyz`, `squareup.com` |
| `bloomberg` | Bloomberg | Financial technology | b | `bloomberg.com`, `bloomberg.net` |
| `blue-origin` | Blue Origin | Space technology | b | `blueorigin.com` |
| `bmc` | BMC Software | IT operations software | b | `bmc.com` |
| `booking` | Booking Holdings | Travel technology | a | `booking.com`, `bookingholdings.com` |
| `boomi` | Boomi | Integration software | b | `boomi.com` |
| `boston-dynamics` | Boston Dynamics | Robotics technology | b | `bostondynamics.com` |
| `brex` | Brex | Financial technology | b | `brex.com` |
| `broadcom` | Broadcom | Semiconductor and infrastructure software | a | `broadcom.com` |
| `broadridge` | Broadridge | Financial technology | a | `broadridge.com` |
| `cadence` | Cadence | Semiconductor design software | a | `cadence.com` |
| `carta` | Carta | Financial technology | b | `carta.com` |
| `celestica` | Celestica | Electronics manufacturing technology | a | `celestica.com` |
| `cisco` | Cisco | Networking technology | a | `cisco.com` |
| `clio` | Clio | Legal technology | b | `clio.com` |
| `cloud-software-group` | Cloud Software Group | Enterprise software | b | `cloud.com`, `citrix.com` |
| `cloudera` | Cloudera | Data platforms | b | `cloudera.com` |
| `cloudflare` | Cloudflare | Internet infrastructure | a | `cloudflare.com` |
| `cohere` | Cohere | Artificial intelligence | c | `cohere.com` |
| `cohesity` | Cohesity | Data security and management | b | `cohesity.com` |
| `coinbase` | Coinbase | Financial technology | a | `coinbase.com` |
| `constellation-software` | Constellation Software | Vertical market software | a | `csisoftware.com` |
| `cornerstone` | Cornerstone OnDemand | Learning technology | b | `csod.com`, `cornerstoneondemand.com` |
| `costar` | CoStar Group | Real estate information technology | a | `costar.com` |
| `coupa` | Coupa | Spend management software | b | `coupa.com` |
| `coveo` | Coveo | Enterprise AI search | a | `coveo.com` |
| `credit-karma` | Credit Karma | Financial technology | a | `creditkarma.com` |
| `crowdstrike` | CrowdStrike | Security technology | a | `crowdstrike.com` |
| `d2l` | D2L | Learning technology | c | `d2l.com` |
| `databricks` | Databricks | Data infrastructure | b | `databricks.com` |
| `datadog` | Datadog | Cloud monitoring | a | `datadoghq.com` |
| `dayforce` | Dayforce | HR technology | a | `dayforce.com`, `ceridian.com` |
| `deel` | Deel | HR technology | b | `deel.com` |
| `dell` | Dell | Computing hardware | a | `dell.com` |
| `descartes` | Descartes | Logistics technology | a | `descartes.com` |
| `discord` | Discord | Consumer technology and platforms | b | `discord.com` |
| `docebo` | Docebo | Learning technology | a | `docebo.com` |
| `doordash` | DoorDash | Local commerce technology | a | `doordash.com` |
| `dropbox` | Dropbox | Cloud collaboration | launch | `dropbox.com` |
| `ebay` | eBay | Commerce technology | a | `ebay.com` |
| `ecobee` | ecobee | Smart home technology | c | `ecobee.com` |
| `electronic-arts` | Electronic Arts | Gaming technology | b | `ea.com` |
| `ellucian` | Ellucian | Education technology | b | `ellucian.com` |
| `enghouse` | Enghouse Systems | Enterprise software | a | `enghouse.com` |
| `epic-games` | Epic Games | Gaming technology | b | `epicgames.com` |
| `epic-systems` | Epic Systems | Health technology | b | `epic.com` |
| `epicor` | Epicor | Enterprise software | b | `epicor.com` |
| `esri` | Esri | Geospatial software | b | `esri.com` |
| `etsy` | Etsy | Commerce technology | a | `etsy.com` |
| `expedia` | Expedia Group | Travel technology | a | `expediagroup.com` |
| `f5` | F5 | Application security and delivery | a | `f5.com` |
| `factset` | FactSet | Financial technology | a | `factset.com` |
| `faire` | Faire | Commerce technology | b | `faire.com` |
| `fico` | FICO | Analytics software | a | `fico.com` |
| `figma` | Figma | Collaborative design technology | launch | `figma.com` |
| `fis` | FIS | Financial technology | a | `fisglobal.com` |
| `fiserv` | Fiserv | Financial technology | a | `fiserv.com` |
| `fivetran` | Fivetran | Data infrastructure | b | `fivetran.com` |
| `flexport` | Flexport | Logistics technology | b | `flexport.com` |
| `fortinet` | Fortinet | Security technology | a | `fortinet.com` |
| `fullscript` | Fullscript | Health technology | b | `fullscript.com` |
| `garmin` | Garmin | Consumer technology | a | `garmin.com` |
| `gen-digital` | Gen Digital | Security technology | a | `gendigital.com` |
| `genesys` | Genesys | Customer experience technology | b | `genesys.com` |
| `genetec` | Genetec | Security technology | b | `genetec.com` |
| `geotab` | Geotab | Telematics technology | b | `geotab.com` |
| `github` | GitHub | Developer platforms | a | `github.com` |
| `global-payments` | Global Payments | Payments technology | a | `globalpayments.com` |
| `global-relay` | Global Relay | Compliance technology | b | `globalrelay.net` |
| `globalfoundries` | GlobalFoundries | Semiconductor manufacturing | a | `gf.com` |
| `godaddy` | GoDaddy | Internet infrastructure | a | `godaddy.com` |
| `gong` | Gong | Revenue technology | b | `gong.io` |
| `google` | Google | Internet products and cloud technology | a | `google.com` |
| `grafana-labs` | Grafana Labs | Developer platforms | b | `grafana.com` |
| `grammarly` | Grammarly | Software and cloud technology | b | `grammarly.com` |
| `gusto` | Gusto | HR technology | b | `gusto.com` |
| `hashicorp` | HashiCorp | Infrastructure software | a | `hashicorp.com` |
| `hopper` | Hopper | Travel technology | b | `hopper.com` |
| `hp` | HP | Computing hardware | a | `hp.com` |
| `hpe` | Hewlett Packard Enterprise | Enterprise technology | a | `hpe.com` |
| `ibm` | IBM | Enterprise technology | a | `ibm.com`, `ca.ibm.com` |
| `indeed` | Indeed | Employment technology | b | `indeed.com` |
| `index-exchange` | Index Exchange | Advertising technology | c | `indexexchange.com` |
| `infor` | Infor | Enterprise software | b | `infor.com` |
| `informatica` | Informatica | Data management software | a | `informatica.com` |
| `instacart` | Instacart | Local commerce technology | c | `instacart.com` |
| `instructure` | Instructure | Education technology | b | `instructure.com` |
| `intel` | Intel | Semiconductor technology | a | `intel.com` |
| `intuit` | Intuit | Financial software | a | `intuit.com` |
| `jack-henry` | Jack Henry | Financial software | a | `jackhenry.com` |
| `juniper` | Juniper Networks | Networking technology | a | `juniper.net` |
| `justworks` | Justworks | HR technology | b | `justworks.com` |
| `kaseya` | Kaseya | IT management software | b | `kaseya.com` |
| `keysight` | Keysight | Electronic test technology | a | `keysight.com` |
| `kinaxis` | Kinaxis | Supply chain software | a | `kinaxis.com` |
| `kla` | KLA | Semiconductor equipment | a | `kla.com` |
| `knowbe4` | KnowBe4 | Security technology | b | `knowbe4.com` |
| `kraken` | Kraken | Financial technology | b | `kraken.com` |
| `lam-research` | Lam Research | Semiconductor equipment | a | `lamresearch.com` |
| `lightspeed` | Lightspeed Commerce | Commerce technology | a | `lightspeedhq.com` |
| `linkedin` | LinkedIn | Professional technology | a | `linkedin.com` |
| `lyft` | Lyft | Mobility technology | launch | `lyft.com` |
| `mailchimp` | Mailchimp | Marketing technology | a | `mailchimp.com` |
| `marvell` | Marvell | Semiconductor technology | a | `marvell.com` |
| `mastercard` | Mastercard | Payments technology | a | `mastercard.com` |
| `mathworks` | MathWorks | Engineering software | b | `mathworks.com` |
| `maxar` | Maxar | Space technology | b | `maxar.com` |
| `mcafee` | McAfee | Security technology | b | `mcafee.com` |
| `mda-space` | MDA Space | Space technology | a | `mda.space` |
| `medallia` | Medallia | Experience management software | b | `medallia.com` |
| `meta` | Meta | Consumer technology | a | `meta.com` |
| `microchip` | Microchip | Semiconductor technology | a | `microchip.com` |
| `micron` | Micron | Semiconductor technology | a | `micron.com` |
| `microsoft` | Microsoft | Software and cloud technology | a | `microsoft.com` |
| `miro` | Miro | Collaboration software | b | `miro.com` |
| `mitel` | Mitel | Business communications technology | b | `mitel.com` |
| `mongodb` | MongoDB | Developer data platforms | a | `mongodb.com` |
| `monolithic-power` | Monolithic Power Systems | Semiconductor technology | a | `monolithicpower.com` |
| `motorola-solutions` | Motorola Solutions | Public safety technology | a | `motorolasolutions.com` |
| `netapp` | NetApp | Data storage technology | a | `netapp.com` |
| `netflix` | Netflix | Streaming technology | a | `netflix.com` |
| `new-relic` | New Relic | Observability software | b | `newrelic.com` |
| `notion` | Notion | Software and cloud technology | b | `makenotion.com` |
| `nuvei` | Nuvei | Payments technology | b | `nuvei.com` |
| `nvidia` | NVIDIA | Accelerated computing | a | `nvidia.com` |
| `nxp` | NXP | Semiconductor technology | a | `nxp.com` |
| `okta` | Okta | Identity security | c | `okta.com` |
| `onsemi` | onsemi | Semiconductor technology | a | `onsemi.com` |
| `openai` | OpenAI | Artificial intelligence | b | `openai.com` |
| `opentext` | OpenText | Enterprise information software | a | `opentext.com` |
| `optimizely` | Optimizely | Digital experience software | b | `optimizely.com` |
| `oracle` | Oracle | Enterprise software and cloud technology | a | `oracle.com` |
| `pagerduty` | PagerDuty | Developer platforms | c | `pagerduty.com` |
| `palantir` | Palantir | Data analytics software | a | `palantir.com` |
| `palo-alto-networks` | Palo Alto Networks | Security technology | a | `paloaltonetworks.com` |
| `paychex` | Paychex | HR technology | a | `paychex.com` |
| `paycom` | Paycom | Human capital software | a | `paycom.com` |
| `paypal` | PayPal | Financial technology | a | `paypal.com` |
| `ping-identity` | Ping Identity | Identity security | b | `pingidentity.com` |
| `pinterest` | Pinterest | Consumer technology | launch | `pinterest.com` |
| `plaid` | Plaid | Financial infrastructure | b | `plaid.com` |
| `pluralsight` | Pluralsight | Learning technology | b | `pluralsight.com` |
| `pointclickcare` | PointClickCare | Health technology | b | `pointclickcare.com` |
| `powerschool` | PowerSchool | Education technology | b | `powerschool.com` |
| `proofpoint` | Proofpoint | Security technology | b | `proofpoint.com` |
| `ptc` | PTC | Industrial software | a | `ptc.com` |
| `qlik` | Qlik | Analytics software | b | `qlik.com` |
| `qorvo` | Qorvo | Semiconductor technology | a | `qorvo.com` |
| `qualcomm` | Qualcomm | Semiconductor technology | a | `qualcomm.com` |
| `qualtrics` | Qualtrics | Experience management software | b | `qualtrics.com` |
| `rakuten-kobo` | Rakuten Kobo | Consumer technology | c | `kobo.com` |
| `ramp` | Ramp | Financial technology | b | `ramp.com` |
| `red-hat` | Red Hat | Open source software | a | `redhat.com` |
| `riot-games` | Riot Games | Gaming technology | b | `riotgames.com` |
| `rippling` | Rippling | HR technology | b | `rippling.com` |
| `robinhood` | Robinhood | Financial technology | a | `robinhood.com` |
| `rockstar-games` | Rockstar Games | Gaming technology | a | `rockstargames.com` |
| `roper` | Roper Technologies | Vertical software | a | `ropertech.com` |
| `salesforce` | Salesforce | Enterprise software | a | `salesforce.com` |
| `sap` | SAP | Enterprise software | c | `sap.com` |
| `sas` | SAS | Analytics software | b | `sas.com` |
| `scale-ai` | Scale AI | Artificial intelligence | b | `scale.com` |
| `scopely` | Scopely | Gaming technology | b | `scopely.com` |
| `seagate` | Seagate | Data storage technology | a | `seagate.com` |
| `seismic` | Seismic | Sales enablement software | b | `seismic.com` |
| `servicenow` | ServiceNow | Enterprise workflow software | a | `servicenow.com` |
| `shopify` | Shopify | Commerce technology | a | `shopify.com` |
| `skyworks` | Skyworks Solutions | Semiconductor technology | a | `skyworksinc.com` |
| `slack` | Slack | Workplace collaboration | a | `slack.com` |
| `smartsheet` | Smartsheet | Work management software | b | `smartsheet.com` |
| `snap` | Snap | Consumer technology | launch | `snap.com` |
| `snowflake` | Snowflake | Cloud data platforms | a | `snowflake.com` |
| `snyk` | Snyk | Security technology | b | `snyk.io` |
| `solarwinds` | SolarWinds | IT management software | b | `solarwinds.com` |
| `spacex` | SpaceX | Space technology | b | `spacex.com` |
| `splunk` | Splunk | Data platforms | a | `splunk.com` |
| `squarespace` | Squarespace | Software and cloud technology | b | `squarespace.com` |
| `stripe` | Stripe | Financial infrastructure | b | `stripe.com` |
| `supermicro` | Supermicro | Computing hardware | a | `supermicro.com` |
| `synopsys` | Synopsys | Semiconductor design software | a | `synopsys.com` |
| `take-two` | Take-Two Interactive | Gaming technology | a | `take2games.com` |
| `tanium` | Tanium | Security technology | b | `tanium.com` |
| `tenstorrent` | Tenstorrent | Semiconductor technology | c | `tenstorrent.com` |
| `teradyne` | Teradyne | Semiconductor equipment | a | `teradyne.com` |
| `tesla` | Tesla | Electric vehicle and energy technology | a | `tesla.com` |
| `texas-instruments` | Texas Instruments | Semiconductor technology | a | `ti.com` |
| `the-trade-desk` | The Trade Desk | Advertising technology | a | `thetradedesk.com` |
| `thomson-reuters` | Thomson Reuters | Information technology | a | `thomsonreuters.com`, `tr.com` |
| `trellix` | Trellix | Security technology | b | `trellix.com` |
| `trimble` | Trimble | Industrial technology | a | `trimble.com` |
| `twilio` | Twilio | Communications infrastructure | launch | `twilio.com` |
| `twitch` | Twitch | Streaming technology | a | `twitch.tv` |
| `tyler-technologies` | Tyler Technologies | Public sector software | a | `tylertech.com` |
| `uber` | Uber | Mobility technology | a | `uber.com` |
| `ubisoft` | Ubisoft | Gaming technology | c | `ubisoft.com` |
| `ukg` | UKG | HR technology | b | `ukg.com` |
| `veeam` | Veeam | Data protection software | b | `veeam.com` |
| `veeva` | Veeva | Life sciences software | a | `veeva.com` |
| `verisign` | VeriSign | Internet infrastructure | a | `verisign.com` |
| `verkada` | Verkada | Security technology | b | `verkada.com` |
| `visa` | Visa | Payments technology | a | `visa.com` |
| `waymo` | Waymo | Autonomous driving technology | a | `waymo.com` |
| `wealthsimple` | Wealthsimple | Financial technology | b | `wealthsimple.com` |
| `western-digital` | Western Digital | Data storage technology | a | `wdc.com` |
| `wiz` | Wiz | Security technology | b | `wiz.io` |
| `workday` | Workday | Enterprise software | a | `workday.com` |
| `x` | X | Consumer technology and platforms | b | `x.com` |
| `xai` | xAI | Artificial intelligence | b | `x.ai` |
| `yahoo` | Yahoo | Internet products | b | `yahooinc.com` |
| `zebra` | Zebra Technologies | Enterprise hardware | a | `zebra.com` |
| `zendesk` | Zendesk | Customer service software | b | `zendesk.com` |
| `zipline` | Zipline | Robotics technology | b | `flyzipline.com` |
| `zoom` | Zoom | Communications technology | a | `zoom.us` |
| `zoox` | Zoox | Mobility technology | a | `zoox.com` |
| `zscaler` | Zscaler | Security technology | a | `zscaler.com` |
| `zynga` | Zynga | Gaming technology | a | `zynga.com` |

### Pending product-owner confirmation (not inserted)

Candidates that are well known but whose clause could not be confirmed from public information:
Ada, Affirm's Toronto headcount is recorded under (c) on the strength of its PayBright
engineering team; FreshBooks, Flipp, Top Hat, Achievers, KOHO, Wattpad, Ritual, League, Vena,
Varicent, Loopio, Xanadu, Waabi (Toronto, engineering headcount unconfirmed); Perplexity, Glean,
Harvey, Vanta, Postman, Vercel, Docker, Mercury, Whatnot, Groq, Cerebras, Cognition, Runway,
Lime (private, headcount near or below 1,000); Roku, Spotify, Unity, Roblox, Reddit, Zillow,
Wayfair, HubSpot, DocuSign, GitLab, Klaviyo, Samsara, Toast, Confluent, Nutanix, Okta-style
public companies outside the three indexes; Nokia, Ericsson, Ciena (engineering in Ottawa and
Montreal, not Toronto); TikTok/ByteDance and the banks with large Toronto technology staff
(product decision). Any of these can be added by a later migration under the clause the
product owner confirms.
