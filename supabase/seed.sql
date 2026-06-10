-- ============================================================================
-- Parts Finder - starter catalog seed
--
-- Run AFTER schema.sql, in the Supabase SQL editor.
-- Re-runnable: every insert uses ON CONFLICT DO NOTHING and looks rows up by
-- name / part number, so running it twice does not create duplicates.
--
-- Data: 16 real-world boiler spares from the original demo catalog.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Suppliers (manufacturers)
-- ----------------------------------------------------------------------------
insert into suppliers (name) values
  ('Vaillant'),
  ('Worcester Bosch'),
  ('Ideal'),
  ('Baxi')
on conflict (name) do nothing;

-- ----------------------------------------------------------------------------
-- Boiler models, linked to their manufacturer
-- ----------------------------------------------------------------------------
insert into boiler_models (name, supplier_id) values
  ('ecoTEC plus 824', (select id from suppliers where name = 'Vaillant')),
  ('ecoTEC plus 831', (select id from suppliers where name = 'Vaillant')),
  ('ecoTEC plus 837', (select id from suppliers where name = 'Vaillant')),
  ('ecoTEC pro 24',   (select id from suppliers where name = 'Vaillant')),
  ('ecoTEC pro 28',   (select id from suppliers where name = 'Vaillant')),
  ('Greenstar 30CDi',     (select id from suppliers where name = 'Worcester Bosch')),
  ('Greenstar 35CDi',     (select id from suppliers where name = 'Worcester Bosch')),
  ('Greenstar 42CDi',     (select id from suppliers where name = 'Worcester Bosch')),
  ('Greenstar 25i',       (select id from suppliers where name = 'Worcester Bosch')),
  ('Greenstar 30i',       (select id from suppliers where name = 'Worcester Bosch')),
  ('Greenstar 8000 Life', (select id from suppliers where name = 'Worcester Bosch')),
  ('Logic Combi 24', (select id from suppliers where name = 'Ideal')),
  ('Logic Combi 30', (select id from suppliers where name = 'Ideal')),
  ('Logic+ 24',      (select id from suppliers where name = 'Ideal')),
  ('Esprit Eco 30',  (select id from suppliers where name = 'Ideal')),
  ('Baxi 600 Combi', (select id from suppliers where name = 'Baxi')),
  ('Baxi 800 Combi', (select id from suppliers where name = 'Baxi')),
  ('Main Eco Compact', (select id from suppliers where name = 'Baxi'))
on conflict (name) do nothing;

-- ----------------------------------------------------------------------------
-- Parts
-- ----------------------------------------------------------------------------
insert into parts
  (part_number, name, category, supplier_id, price, stock, replacement, description, keywords, supersedes)
values
  ('0020132683', 'Diverter Valve Complete', 'Hydraulics',
   (select id from suppliers where name = 'Vaillant'), 93.50, 'in', true,
   'Switches the flow of hot water between the radiators and the taps. Classic fault: heating works but there is no hot water, or the reverse. Supersedes part 178978.',
   array['diverter','valve','178978','hot water but no heating','heating but no hot water','stuck valve'],
   '178978'),

  ('0020059717', 'Water Pressure Sensor', 'Sensors',
   (select id from suppliers where name = 'Vaillant'), 27.58, 'in', true,
   'Reports the system water pressure to the control board. A bad sensor triggers false low-pressure warnings (F.22) and shutdowns.',
   array['pressure','low pressure','f22','error code','sensor','pressure drop'],
   null),

  ('181051', 'Expansion Vessel 10L', 'Hydraulics',
   (select id from suppliers where name = 'Vaillant'), 95.00, 'low', true,
   'Rectangular 10 litre vessel with 3/8 inch connection. Absorbs the expansion of water as it heats; when it fails, pressure climbs and the relief valve drips.',
   array['expansion vessel','pressure rises','pressure drop','prv discharge','losing pressure'],
   null),

  ('193593', 'Fan Assembly', 'Combustion',
   (select id from suppliers where name = 'Vaillant'), 233.00, 'in', true,
   'Pushes air in and exhaust gases out of the boiler. A whining noise or a fan-fault error code means it is wearing out.',
   array['fan','noisy','whining','fan fault','no ignition','air pressure'],
   null),

  ('0010030632', 'High Efficiency Pump', 'Hydraulics',
   (select id from suppliers where name = 'Vaillant'), 190.00, 'in', true,
   'Pushes hot water around the radiator circuit. Cold radiators while the boiler runs, or a loud humming, usually point here.',
   array['pump','circulation','no circulation','radiators cold','noisy pump','humming'],
   null),

  ('87161165680', 'Ignition Electrode Assembly', 'Ignition',
   (select id from suppliers where name = 'Worcester Bosch'), 34.95, 'in', true,
   'Generates the spark that lights the gas burner, with separate leads for CDi models. A worn electrode means the boiler clicks repeatedly but never lights.',
   array['spark','no ignition','lockout','won''t start','fails to light','electrode'],
   null),

  ('87161163810', 'Electrode Kit', 'Ignition',
   (select id from suppliers where name = 'Worcester Bosch'), 24.50, 'in', true,
   'Replacement ignition and sensing electrodes for Greenstar i-series boilers. A standard item during annual service when sparking gets unreliable.',
   array['electrode','spark','no ignition','lockout','service kit'],
   null),

  ('87161064450', 'Automatic Air Vent', 'Hydraulics',
   (select id from suppliers where name = 'Worcester Bosch'), 19.95, 'in', false,
   'Automatically releases trapped air from the heating circuit. Gurgling noises and cold radiator tops are the usual signs it has stuck.',
   array['air vent','aav','gurgling','air in system','cold radiator top','bleeding'],
   null),

  ('8716122562', 'Flow Sensor Assembly', 'Sensors',
   (select id from suppliers where name = 'Worcester Bosch'), 36.00, 'low', true,
   'Detects when a hot tap is opened so the boiler fires for hot water. No hot water with working heating often points here. Supersedes part 87161157540.',
   array['flow sensor','87161157540','no hot water','turbine','dhw','tap'],
   '87161157540'),

  ('175591', 'Ignition Electrode', 'Ignition',
   (select id from suppliers where name = 'Ideal'), 23.26, 'in', true,
   'Generates the spark that lights the gas burner. A worn electrode means repeated clicking, ignition lockouts and an L2 fault code.',
   array['spark','no ignition','lockout','l2','won''t start','fails to light','electrode'],
   null),

  ('175592', 'Flame Detection Electrode', 'Ignition',
   (select id from suppliers where name = 'Ideal'), 19.80, 'in', true,
   'Confirms to the control board that a flame is actually burning. A faulty electrode makes the boiler light and then shut down seconds later.',
   array['flame sensor','detection','lockout','flame loss','no ignition','intermittent'],
   null),

  ('175413', 'Fan Assembly', 'Combustion',
   (select id from suppliers where name = 'Ideal'), 138.00, 'in', true,
   'Pushes air and exhaust gases through the boiler. A whining noise or an F3 fan-fault code means it is wearing out.',
   array['fan','noisy','whining','f3','fan fault','no ignition','air pressure'],
   null),

  ('175572', 'Burner Gasket', 'Combustion',
   (select id from suppliers where name = 'Ideal'), 12.40, 'in', false,
   'Heat-resistant seal replaced during the annual service to keep combustion gases safely inside the boiler.',
   array['gasket','seal','service kit','annual service','burner'],
   null),

  ('176610', 'Pressure Relief Valve Kit', 'Hydraulics',
   (select id from suppliers where name = 'Ideal'), 28.75, 'in', false,
   'Safety valve that discharges water if system pressure gets too high. Replaced when it weeps constantly after a pressure spike.',
   array['prv','pressure relief','safety valve','dripping outside','discharge','leaking'],
   null),

  ('175660', 'Flow Turbine', 'Sensors',
   (select id from suppliers where name = 'Ideal'), 31.20, 'out', true,
   'Spins as hot water is drawn and tells the boiler to fire. A jammed turbine means taps run cold while the heating still works.',
   array['turbine','flow sensor','no hot water','dhw','tap','intermittent hot water'],
   null),

  ('7212347', 'Main Control Board (PCB)', 'Controls',
   (select id from suppliers where name = 'Baxi'), 168.00, 'low', true,
   'The brain of the boiler: sequences ignition, pump and fan. Replaced when the boiler is completely dead or throws random error codes.',
   array['pcb','circuit board','no power','dead display','error code','control board'],
   null)
on conflict (part_number) do nothing;

-- ----------------------------------------------------------------------------
-- Part <-> boiler model links
-- ----------------------------------------------------------------------------
insert into part_models (part_id, model_id)
select p.id, m.id
from parts p
join boiler_models m on (p.part_number, m.name) in (
  ('0020132683', 'ecoTEC plus 824'), ('0020132683', 'ecoTEC plus 831'), ('0020132683', 'ecoTEC plus 837'), ('0020132683', 'ecoTEC pro 24'), ('0020132683', 'ecoTEC pro 28'),
  ('0020059717', 'ecoTEC plus 824'), ('0020059717', 'ecoTEC plus 831'), ('0020059717', 'ecoTEC plus 837'), ('0020059717', 'ecoTEC pro 24'), ('0020059717', 'ecoTEC pro 28'),
  ('181051', 'ecoTEC plus 824'), ('181051', 'ecoTEC plus 831'),
  ('193593', 'ecoTEC plus 824'), ('193593', 'ecoTEC plus 831'), ('193593', 'ecoTEC plus 837'), ('193593', 'ecoTEC pro 24'), ('193593', 'ecoTEC pro 28'),
  ('0010030632', 'ecoTEC plus 824'), ('0010030632', 'ecoTEC plus 831'), ('0010030632', 'ecoTEC plus 837'), ('0010030632', 'ecoTEC pro 24'), ('0010030632', 'ecoTEC pro 28'),
  ('87161165680', 'Greenstar 30CDi'), ('87161165680', 'Greenstar 35CDi'), ('87161165680', 'Greenstar 42CDi'),
  ('87161163810', 'Greenstar 25i'), ('87161163810', 'Greenstar 30i'),
  ('87161064450', 'Greenstar 25i'), ('87161064450', 'Greenstar 30i'), ('87161064450', 'Greenstar 30CDi'), ('87161064450', 'Greenstar 8000 Life'),
  ('8716122562', 'Greenstar 25i'), ('8716122562', 'Greenstar 30i'), ('8716122562', 'Greenstar 30CDi'),
  ('175591', 'Logic Combi 24'), ('175591', 'Logic Combi 30'), ('175591', 'Logic+ 24'), ('175591', 'Esprit Eco 30'),
  ('175592', 'Logic Combi 24'), ('175592', 'Logic Combi 30'), ('175592', 'Logic+ 24'), ('175592', 'Esprit Eco 30'),
  ('175413', 'Logic Combi 24'), ('175413', 'Logic Combi 30'),
  ('175572', 'Logic Combi 24'), ('175572', 'Logic Combi 30'), ('175572', 'Logic+ 24'),
  ('176610', 'Logic Combi 24'), ('176610', 'Logic Combi 30'), ('176610', 'Logic+ 24'),
  ('175660', 'Logic Combi 24'), ('175660', 'Logic Combi 30'),
  ('7212347', 'Baxi 600 Combi'), ('7212347', 'Baxi 800 Combi'), ('7212347', 'Main Eco Compact')
)
on conflict do nothing;
