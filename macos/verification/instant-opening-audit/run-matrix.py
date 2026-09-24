"""Run sequential independent processes, so benchmark scenarios do not compete for CPU."""
import json
from pathlib import Path
import statistics
import subprocess
import sys

executable = sys.argv[1]
scenarios = [
    ['canopy', '30', '--prepare'],
    ['canopy', '100', '--prepare'],
    ['canopy', '300', '--prepare'],
    ['canopy', '100', '--prime-scene'],
    ['canopy', '300', '--prime-scene'],
    ['canopy', '100', '--churn'],
    ['canopy', '100'],
    ['canopy', '100', '--prepare', '--prepare-between'],
    ['canopy', '100', '--prepare', '--draw'],
    ['canopy', '100', '--prepare', '--glass'],
    ['canopy', '100', '--prime-scene', '--glass'],
]
results = []
output = Path(__file__).parent / 'opening-results.json'
for scenario in scenarios:
    for repetition in range(2):
        process = subprocess.run([executable, *scenario], capture_output=True, text=True, check=True)
        result = json.loads(process.stdout)
        results.append(result)
        output.write_text(json.dumps(results, indent=2) + '\n')
        first = result['samples'][0]
        repeated = statistics.median(s['present_ms']+s['layout_ms'] for s in result['samples'][2:])
        print(' '.join(scenario), repetition+1,
              f"first={first['present_ms']+first['layout_ms']:.2f} repeated={repeated:.2f} prepared_rows={result['rows_prepared']} new_rows={first['new_rows']} views={first['views']}", flush=True)
