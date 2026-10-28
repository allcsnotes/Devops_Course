"""sli.py <run> - a first SLI from the real run (module 17 makes it an SLO):
good request = status 200 AND answered in under 300 ms (as the users saw it); SLI = good / all requests"""
import csv, os, sys
D = os.path.dirname(os.path.abspath(__file__)); RUN = sys.argv[1]
R = [r for r in csv.reader(open(f"{D}/runs/{RUN}.csv")) if r]
good = [r for r in R if r[2] == "200" and int(r[3]) < 300]
print(f"requests {len(R)}   good {len(good)}   SLI {100 * len(good) / len(R):.2f} %")
