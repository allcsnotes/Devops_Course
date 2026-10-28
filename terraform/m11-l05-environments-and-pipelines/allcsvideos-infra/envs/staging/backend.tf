terraform {
  backend "pg" {
    schema_name          = "staging" # this environment's own state
    skip_schema_creation = true      # created once by the state admin
    skip_table_creation  = true
    skip_index_creation  = true
  }
}
