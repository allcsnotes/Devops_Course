# the to-do list that git rebase -i HEAD~4 opens in nano, printed from a scratch copy of the untouched scenario 9 repository
@rm -rf /tmp/todo-09 && cp -a ~/rescue/09-squash /tmp/todo-09
(cd /tmp/todo-09 && GIT_SEQUENCE_EDITOR='grep -v -e "^#" -e "^$"' git rebase -i HEAD~4 2>/dev/null)
