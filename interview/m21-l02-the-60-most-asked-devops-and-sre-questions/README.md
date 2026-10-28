# M21-L02 · The 60 Most-Asked DevOps and SRE Questions
> Video: Module 21, Lesson 2. Watch it first, then follow along here.

## What you'll learn
- Sixty questions that come up again and again in DevOps and SRE interviews, with crisp model answers
- The key points an interviewer listens for, and the follow-ups they may ask
- Which lesson of this course teaches each answer, so you know where to go back
- How to answer a question you have never seen before

## Files in this folder
| File | What it is |
|---|---|
| `questions.md` | All 60 questions with a fuller written model answer, key points, follow-ups and a link to the lesson that teaches it |

## Key ideas

The sixty questions are grouped in nine blocks, in course order. It is not a ranked list, and there are no frequency
statistics behind it.

| Block | Topic | Questions |
|---|---|---|
| 1 | Linux and the shell | Q1-Q7 |
| 2 | Networking | Q8-Q13 |
| 3 | Git | Q14-Q17 |
| 4 | Docker and containers | Q18-Q24 |
| 5 | CI/CD and releases | Q25-Q31 |
| 6 | Cloud, IaC and config | Q32-Q38 |
| 7 | Kubernetes | Q39-Q46 |
| 8 | Observability, SRE and incidents | Q47-Q53 |
| 9 | Security, platform and cost | Q54-Q60 |

**How to use `questions.md`:** read the question, pause, answer out loud in two or three sentences, then compare with
the model answer. Make sure you would say every key point, in your own words.

**Keep the conditions.** The hook of the video: "A container exits with code 137. Why?" - "It ran out of memory" is
only one cause. 137 is 128 + 9, a SIGKILL. In [M06-L03](../../docker/m06-l03-running-containers/) the container was
not out of memory at all; `docker stop` sent SIGTERM, the app ignored it, and Docker killed it after the grace period:
```
$ time docker stop stubborn
real	0m10.125s
$ docker inspect --format 'exit={{.State.ExitCode}} oom={{.State.OOMKilled}}' stubborn
exit=137 oom=false
```
Precise beats confident.

**A question you've never seen:** say what you know for certain, reason out loud from how the system works, name the
trade-off, and say exactly how you'd check - the command you'd run and the output you'd expect.

### Recap
1. **Answer in a shape:** what it is, how it works, and the trade-off or failure mode, in two or three sentences.
2. **Keep the conditions:** exit 137 is a kill signal; out of memory is only one cause.
3. **Back it with evidence:** name the command you'd run and what you'd expect to see.

## Try it yourself
1. Go through one block of `questions.md` a day: cover the answer, say yours out loud, then compare against the key points.
2. For every question you missed, open the "Covered in" lesson link and redo that part of the lesson.
3. Ask a friend to pick random question numbers and add "always?" or "why?" after each of your answers.

## Next
[M21-L03 · The Scenario Round](../m21-l03-the-scenario-round/)
