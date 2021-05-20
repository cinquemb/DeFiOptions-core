import os
import json

base_sim_path = './sim_output/'
out_put_files = [x for x in os.listdir(base_sim_path) if '.txt' in x]

sim_symbols_sold_map = {}
sim_symbols_sold_unver_map = {}


for sim_raw_file in out_put_files[-2:]:
	sim_symbols_sold_map[sim_raw_file] = {'calls': 0, 'puts': 0, 'symbols': {}}
	with open(base_sim_path+sim_raw_file, 'r+') as f:
		i = 0
		cached_symbols = []
		for row in f:

			if "tx passed:" in row:
				fails = row.split('tx fails:')[-1].strip().split('],')[0]
				passed = row.split('tx passed:')[-1].strip()
				cached_symbols = []

				for ptx in passed.split('},'):
					if "'type': 'sell'" in ptx:
						(tt, th, tv, tvd, tp, ts) = ptx.strip().split(',')

						temp_sym = ts.strip().replace(
							"'symbol': '",
						'').replace("'", "").replace("}]", "")

						temp_vol = int(tv.strip().replace(
							"'volume': Balance(",
						'').replace("'", "").replace("}]", "")) / 10.**18
	
						if temp_sym not in sim_symbols_sold_map[sim_raw_file]['symbols']:
							sim_symbols_sold_map[sim_raw_file]['symbols'][temp_sym] = True

						if '-EP-' in temp_sym:
							sim_symbols_sold_map[sim_raw_file]['puts'] += temp_vol

						if '-EC-' in temp_sym:
							sim_symbols_sold_map[sim_raw_file]['calls'] += temp_vol
			i+=1


	print(sim_raw_file, 'total c/p: ', sim_symbols_sold_map[sim_raw_file]['calls'] / (sim_symbols_sold_map[sim_raw_file]['puts']))
print('total: ' + json.dumps(sim_symbols_sold_map, indent=4))

