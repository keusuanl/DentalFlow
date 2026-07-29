# Pending Terraform Applies

Tracks infrastructure that has been written and validated (`terraform plan` succeeds)
but deliberately NOT yet applied to AWS - to avoid paying for resources before they
have an actual workload using them.

## Status

| Module | Validated (plan) | Applied | Notes |
|---|---|---|---|
| infra/modules/networking | Yes - 14 resources, no errors | No | VPC has no dependent workload yet (no ECS/RDS). Apply once ECS or RDS module is ready to consume it - avoids paying for idle NAT Gateway + EIP. |

| infra/modules/s3 | Yes - 4 resources, no errors | No | No workload uses this bucket yet (no backend/frontend built). Apply once presigned URL generation is being tested, or bundle with ECS apply. |

| infra/modules/sqs_sns | Yes - 8 resources, no errors | No | No consumer built yet (no backend). Apply alongside ECS/backend once something can actually process these queues. |

## When to update this file
- Add a row when a new module is written and plan-validated but not applied.
- Update "Applied" to Yes once `terraform apply` is actually run for that module,
  and note the date.
- Before ending a work session, check this file: anything marked Applied that's no
  longer needed should be destroyed (`terraform destroy`) to avoid ongoing cost.
