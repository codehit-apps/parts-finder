-- ============================================================================
-- Parts Finder - starter catalog seed
--
-- Run AFTER schema.sql, in the Supabase SQL editor.
-- Re-runnable: every insert uses ON CONFLICT DO NOTHING and looks rows up by
-- name / part number, so running it twice does not create duplicates.
--
-- Data: 100 real-world boiler spares -- 16 core demo parts plus 84 generated as
-- 12 common spare-part types across 7 manufacturers (see the bottom of the file).
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

-- ============================================================================
-- Extended catalog: brings the seed up to 100 parts for realistic scale.
--
-- Adds three more manufacturers and twenty more boiler models, then generates
-- 84 parts as 12 common spare-part types x 7 manufacturers (each with its own
-- part-number prefix and price level). 16 core + 84 = 100. Still re-runnable.
-- ============================================================================

-- More manufacturers
insert into suppliers (name) values
  ('Glow-worm'),
  ('Viessmann'),
  ('Alpha')
on conflict (name) do nothing;

-- More boiler models (existing brands get extra ranges; new brands their lineup)
insert into boiler_models (name, supplier_id) values
  ('ecoTEC plus 615',  (select id from suppliers where name = 'Vaillant')),
  ('ecoTEC plus 630',  (select id from suppliers where name = 'Vaillant')),
  ('ecoFIT pure 830',  (select id from suppliers where name = 'Vaillant')),
  ('Greenstar 4000 30',        (select id from suppliers where name = 'Worcester Bosch')),
  ('Greenstar 8000 Style 35',  (select id from suppliers where name = 'Worcester Bosch')),
  ('Greenstar CDi Classic 30', (select id from suppliers where name = 'Worcester Bosch')),
  ('Logic Max Combi 30', (select id from suppliers where name = 'Ideal')),
  ('Vogue Gen2 C40',     (select id from suppliers where name = 'Ideal')),
  ('800 Heat 25',        (select id from suppliers where name = 'Baxi')),
  ('Platinum+ 33 Combi', (select id from suppliers where name = 'Baxi')),
  ('Duo-tec Combi 2 28', (select id from suppliers where name = 'Baxi')),
  ('Energy 25c',      (select id from suppliers where name = 'Glow-worm')),
  ('Energy 35 Store', (select id from suppliers where name = 'Glow-worm')),
  ('Ultimate3 30',    (select id from suppliers where name = 'Glow-worm')),
  ('Easicom 3 28',    (select id from suppliers where name = 'Glow-worm')),
  ('Vitodens 050-W 30', (select id from suppliers where name = 'Viessmann')),
  ('Vitodens 100-W 35', (select id from suppliers where name = 'Viessmann')),
  ('Vitodens 111-W',    (select id from suppliers where name = 'Viessmann')),
  ('E-Tec Plus 28',  (select id from suppliers where name = 'Alpha')),
  ('ProTec Plus 33', (select id from suppliers where name = 'Alpha'))
on conflict (name) do nothing;

-- 84 parts = 12 spare-part types x 7 manufacturers. Each type carries its own
-- name/category/description/keywords; each manufacturer its own part-number
-- prefix (so numbers are unique) and a price multiplier. part_number is
-- prefix || NN, e.g. Vaillant Gas Valve (type 05) -> 0020201005.
insert into parts
  (part_number, name, category, supplier_id, price, stock, replacement, description, keywords)
select
  brand.prefix || lpad(t.idx::text, 2, '0'),
  t.name,
  t.category,
  (select id from suppliers where name = brand.supplier),
  round((t.base_price * brand.price_factor)::numeric, 2),
  (array['in','in','low','in','out','in','in','low','in','out','in','in'])[t.idx],
  t.replacement,
  t.description,
  t.keywords
from (values
  (1,  'Plate Heat Exchanger',     'Hydraulics', 118.00, true,
       'Transfers heat from the primary circuit to the domestic hot water. Furring or blockage shows as lukewarm or fluctuating hot water.',
       array['plate heat exchanger','phe','lukewarm hot water','dhw','limescale','no hot water']),
  (2,  'Primary Heat Exchanger',   'Combustion', 360.00, true,
       'The main heat exchanger where the burner heats the system water. Replaced after corrosion, leaks or repeated overheating faults.',
       array['heat exchanger','primary','leak','overheat','corrosion','knocking']),
  (3,  'Diverter Valve Cartridge', 'Hydraulics', 58.00, true,
       'The internal cartridge of the diverter valve. A worn cartridge lets hot water bleed into the heating, or the reverse.',
       array['diverter','cartridge','valve','no hot water','heating stays on','stuck']),
  (4,  'Diverter Valve Motor',     'Controls', 72.00, true,
       'The electric actuator that drives the diverter valve between heating and hot water. Failure leaves the boiler stuck in one mode.',
       array['diverter motor','actuator','valve motor','stuck in heating','no hot water']),
  (5,  'Gas Valve',                'Gas', 145.00, true,
       'Meters gas to the burner under control of the PCB. Faults cause ignition lockouts, a low flame or gas-valve error codes.',
       array['gas valve','no ignition','lockout','low flame','gas','error code']),
  (6,  'Venturi and Gas Manifold', 'Gas', 84.00, true,
       'Mixes gas and air in the correct ratio before the burner. A blocked venturi causes poor combustion and lockouts.',
       array['venturi','gas manifold','combustion','lockout','flue gas','co']),
  (7,  'Flue Temperature Sensor',  'Sensors', 24.00, true,
       'Monitors flue gas temperature for safe condensing operation. A faulty sensor trips overheat or flue faults.',
       array['flue sensor','flue temperature','overheat','ntc','error code']),
  (8,  'Return NTC Sensor',        'Sensors', 18.50, true,
       'Thermistor reading the return water temperature so the PCB can modulate the burner. Drift causes erratic temperatures.',
       array['ntc','return sensor','thermistor','temperature','modulation','erratic heat']),
  (9,  'Overheat Thermostat',      'Sensors', 22.00, true,
       'Safety cut-out that shuts the boiler down if it gets too hot. A tripped or failed stat causes intermittent lockouts.',
       array['overheat','thermostat','cut out','lockout','safety','overheating']),
  (10, 'Ignition Lead Set',        'Ignition', 21.00, false,
       'High-tension leads carrying the spark to the ignition electrode. Cracked leads cause weak sparks and failed ignition.',
       array['ignition lead','ht lead','spark','no ignition','lockout']),
  (11, 'Condensate Trap',          'Flue', 28.00, false,
       'Collects and drains acidic condensate while blocking flue gases. A blocked or frozen trap causes gurgling and lockouts.',
       array['condensate trap','siphon','blocked condensate','frozen','gurgling']),
  (12, 'Pressure Gauge',           'Controls', 17.50, false,
       'Displays system water pressure on the front of the boiler. Replaced when the needle sticks or reads incorrectly.',
       array['pressure gauge','gauge','pressure reading','needle stuck','low pressure'])
) as t(idx, name, category, base_price, replacement, description, keywords)
cross join (values
  ('Vaillant',        '00202010', 1.00),
  ('Worcester Bosch', '87162200', 1.05),
  ('Ideal',           '1770',     0.92),
  ('Baxi',            '72200',    0.95),
  ('Glow-worm',       '20008100', 0.90),
  ('Viessmann',       '78260',    1.12),
  ('Alpha',           '3.0250',   0.88)
) as brand(supplier, prefix, price_factor)
on conflict (part_number) do nothing;

-- Link each generated part to its manufacturer's boiler models. (Restricted to
-- the generated part-number prefixes so the 16 core parts above keep their
-- hand-picked model lists.)
insert into part_models (part_id, model_id)
select p.id, m.id
from parts p
join boiler_models m on m.supplier_id = p.supplier_id
where p.part_number like '00202010%'
   or p.part_number like '87162200%'
   or p.part_number like '1770%'
   or p.part_number like '7220%'
   or p.part_number like '20008100%'
   or p.part_number like '78260%'
   or p.part_number like '3.0250%'
on conflict do nothing;
