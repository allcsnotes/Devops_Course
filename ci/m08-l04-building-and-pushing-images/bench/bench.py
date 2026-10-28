import time
t = time.perf_counter()
sum(i * i for i in range(5_000_000))
print(f"{time.perf_counter() - t:.2f} s")
