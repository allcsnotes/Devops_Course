# allcsvideos guardrails for IAM, as code (Rego, run by conftest)
package main

# Terraform: statements of every aws_iam_policy_document
tf_stmt contains [name, s] if {
  some name, i, j
  s := input.data.aws_iam_policy_document[name][i].statement[j]
}

# plain JSON policy documents (Statement may be one object or a list)
json_stmt contains s if {
  s := input.Statement[_]
}
json_stmt contains input.Statement if is_object(input.Statement)

as_list(x) := x if is_array(x)
as_list(x) := [x] if is_string(x)

deny contains msg if {
  some [name, s] in tf_stmt
  "*" in s.actions
  msg := sprintf("%s: Action \"*\" allows every API call", [name])
}

deny contains msg if {
  some [name, s] in tf_stmt
  "iam:PassRole" in s.actions
  "*" in s.resources
  msg := sprintf("%s: iam:PassRole on every role", [name])
}

deny contains msg if {
  some s in json_stmt
  s.Effect == "Allow"
  "*" in as_list(s.Action)
  msg := "policy: Action \"*\" allows every API call"
}

deny contains msg if {
  some s in json_stmt
  s.Effect == "Allow"
  "iam:PassRole" in as_list(s.Action)
  "*" in as_list(s.Resource)
  msg := "policy: iam:PassRole on every role"
}

deny contains msg if {
  some name, i
  role := input.resource.aws_iam_role[name][i]
  not role.permissions_boundary
  msg := sprintf("aws_iam_role.%s: no permissions boundary", [name])
}
