cd ~/rescue/06-stash
git status -s
git stash list
git stash push -u -m "docker checks WIP"
git status -s
git stash list
git switch -c fix/readme-typo origin/main
grep -n helth README.md
sed -i 's/helth/health/' README.md
git commit -am "README: fix a typo"
git push -u origin fix/readme-typo
git switch feature/check-docker
git stash pop stash@{0}
git status -s
git stash list
git stash show -p stash@{0}
git stash drop stash@{0}
git stash list
