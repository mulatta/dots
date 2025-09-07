terraform {
  before_hook "reset_lock" {
    commands = ["init"]
    execute = ["rm", "-f", ".terraform.lock.hcl"]
  }
}
