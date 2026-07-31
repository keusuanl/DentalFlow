# Project Tracking - Pending Applies & Documentation Debt

## 1. Pending Terraform Applies

Tracks infrastructure that has been written and validated (`terraform plan` succeeds)
but deliberately NOT yet applied to AWS, to avoid paying for resources before they
have an actual workload using them.

| Module | Validated (plan) | Applied | Notes |
|---|---|---|---|
| infra/modules/networking | Yes - 14 resources, no errors | No | VPC has no dependent workload yet (no ECS/RDS). Apply once ECS or RDS module is ready to consume it, to avoid paying for idle NAT Gateway and EIP. |
| infra/modules/s3 | Yes - 5 resources, no errors | No | No workload uses this bucket yet (no backend/frontend built). Apply once presigned URL generation is being tested, or bundle with ECS apply. |
| infra/modules/sqs_sns | Yes - 8 resources, no errors | No | No consumer built yet (no backend). Apply alongside ECS/backend once something can actually process these queues. |
| infra/modules/ecs | Partial - IAM roles applied for real (2 resources), remainder still being written | Partial | IAM task execution role and task role are live in AWS. Security groups, ALB, CloudWatch log group, ECS cluster, task definition, and service still need to be written before the module is complete. |

### When to update this section
- Add a row when a new module is written and plan-validated but not applied.
- Update "Applied" to Yes once `terraform apply` is actually run for that module,
  and note the date.
- Before ending a work session, check this file: anything marked Applied that's no
  longer needed should be destroyed (`terraform destroy`) to avoid ongoing cost.

## 2. Pending ADRs (documentation debt)

Tracks decisions that have been made and acted on in code, but not yet formally
written up as a numbered ADR.

| ADR | Status | Notes |
|---|---|---|
| IAM scoping strategy for local dev credentials | Not written | Covers why PowerUserAccess was chosen over AdministratorAccess, why the narrow dentalflow-role-management policy exists, why it must be attached manually via root or console (self-privilege-escalation prevention), and the full discovered permission list (CreateRole, ListRolePolicies, ListAttachedRolePolicies, ListInstanceProfilesForRole, and others) with the real incident story as justification. Referenced informally in ADR-004. Deserves its own numbered ADR since it is a standalone, recurring security decision. |

### When to update this section
- Add a row whenever a real decision gets made and implemented in code or console
  before its ADR is written.
- Remove the row once the ADR is written and committed, replacing it with a
  cross-reference in the relevant module or ADR instead.
