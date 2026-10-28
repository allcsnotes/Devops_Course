# unit tests for the guardrails: conftest verify
package main

test_star_action_denied if {
  deny["policy: Action \"*\" allows every API call"] with input as
    {"Statement": [{"Effect": "Allow", "Action": "*", "Resource": "*"}]}
}

test_scoped_policy_allowed if {
  count(deny) == 0 with input as
    {"Statement": [{"Effect": "Allow", "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::allcs-media/*"}]}
}
