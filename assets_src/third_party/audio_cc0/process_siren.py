import sys, array, wave, subprocess, math
src, out_ogg = sys.argv[1], sys.argv[2]
w = wave.open(src, "rb"); n = w.getnframes(); a = array.array("h"); a.frombytes(w.readframes(n)); w.close()
rising = [i for i in range(1, len(a)) if a[i-1] < 0 <= a[i]]
start, end = rising[0], rising[-1]
a = a[start:end]
peak = max(max(a), -min(a)) or 1
k = (10 ** (-1/20) * 32767) / peak
a = array.array("h", [max(-32767, min(32767, int(round(v*k)))) for v in a])
tmp = src.replace(".wav", "_loop.wav")
ww = wave.open(tmp, "wb"); ww.setnchannels(1); ww.setsampwidth(2); ww.setframerate(44100); ww.writeframes(a.tobytes()); ww.close()
subprocess.run(["ffmpeg","-y","-v","error","-i",tmp,"-c:a","libvorbis","-q:a","5",out_ogg],check=True)
print("loop seconds %.3f, peak %d, bytes %d" % (len(a)/44100, max(max(a), -min(a)), __import__("os").path.getsize(out_ogg)))
