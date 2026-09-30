# Secure VPC Reference Architecture

AWS VPC 핵심 개념을 Terraform으로 직접 구현하고 실제 EC2/Session Manager를 통해 동작을 
검증한 레퍼런스 아키텍처입니다. AZ 이중화, NAT Gateway 설계, SSH 없는 접속(Session Manager),
IMDSv2 강제 등 보안 모범 사례를 코드로 구현하고, 각 설계 결정의 근거를 문서화했습니다.

---

## 아키텍처

```
                              Internet
                                 │
                          ┌──────┴──────┐
                          │     IGW     │
                          └──────┬──────┘
                                 │
        ┌────────────────────────────────────────────┐
        │                    VPC (10.0.0.0/16)         │
        │                                               │
        │   AZ-a                        AZ-b            │
        │  ┌─────────────────┐        ┌─────────────────┐
        │  │ Public Subnet    │        │ Public Subnet    │
        │  │ 10.0.1.0/24      │        │ 10.0.3.0/24      │
        │  │  ┌────────────┐  │        │  ┌────────────┐  │
        │  │  │  EC2       │  │        │  │            │  │
        │  │  │(public_ec2)│  │        │  │            │  │
        │  │  └────────────┘  │        │  └────────────┘  │
        │  │  ┌────────────┐  │        │  ┌────────────┐  │
        │  │  │ NAT-GW-A   │  │        │  │ NAT-GW-B   │  │
        │  │  └─────┬──────┘  │        │  └─────┬──────┘  │
        │  └────────┼─────────┘        └────────┼─────────┘
        │            │                            │
        │  ┌─────────┼─────────┐        ┌─────────┼─────────┐
        │  │ Private Subnet     │        │ Private Subnet     │
        │  │ 10.0.2.0/24        │        │ 10.0.4.0/24        │
        │  │  ┌────────────┐    │        │                    │
        │  │  │  EC2        │◄──┘        │                    │
        │  │  │(private_ec2)│             │                    │
        │  │  └────────────┘             │                    │
        │  │  [Interface Endpoints:      │                    │
        │  │   ssm / ssmmessages /       │                    │
        │  │   ec2messages]              │                    │
        │  └────────────────────┘        └────────────────────┘
        └────────────────────────────────────────────┘
```

- **Public Subnet**: IGW로 직접 라우팅. 인터넷 양방향 통신 가능.
- **Private Subnet**: NAT Gateway를 통해서만 아웃바운드. 퍼블릭 IP 없음.
- **NAT Gateway**: AZ마다 별도 배치 (이유는 아래 설계 결정 참고).
- **VPC Endpoint**: Private 인스턴스가 인터넷 없이 SSM과 통신하기 위한 사설 경로.

---

## 설계 결정과 이유

### 1. NAT Gateway를 AZ마다 별도로 배치

NAT Gateway는 VPC 전체가 아니라 **특정 AZ에 종속된 리소스**다. 하나의 NAT를
여러 AZ의 Private Subnet이 공유하면, 그 NAT가 위치한 AZ에 장애가 발생하는
순간 나머지 AZ까지 전부 인터넷 아웃바운드를 잃는 숨은 단일장애점(SPOF)이
생긴다. 비용은 2배가 되지만(NAT Gateway는 시간당 + 트래픽당 과금), 고가용성
관점에서 AZ별 이중화를 표준으로 채택했다.

### 2. SSH 대신 AWS Systems Manager Session Manager

SSH는 포트 22를 인바운드로 열어야 하고, 키 페어 관리 부담이 있으며,
기본적으로 접속 로그가 남지 않는다. Session Manager는:

- **포트를 아예 열지 않는다** — SG에 인바운드 규칙 자체가 필요 없어 공격
  표면이 근본적으로 줄어든다.
- **IAM으로 접속 권한을 통제한다** — 누가 어느 인스턴스에 접속 가능한지가
  IAM 정책으로 관리된다.
- **모든 세션이 CloudTrail에 기록된다** — SSH에는 없는 감사 추적성을
  기본 제공한다.

이 레포의 EC2에는 `aws_key_pair`가 존재하지 않으며, SG에 22번 포트 규칙이
없다.

### 3. Interface VPC Endpoint를 두 AZ 모두에 배치

Interface VPC Endpoint(PrivateLink)는 지정한 subnet(= 지정한 AZ)에만
ENI가 생성되는 **AZ 단위 리소스**다. 한 AZ에만 생성하면 다른 AZ의
인스턴스는 그 ENI에 도달하기 위해 cross-AZ 호출을 하게 되어 불필요한
지연과 데이터 전송 비용이 발생한다. `ssm`, `ssmmessages`, `ec2messages`
세 Endpoint 모두 AZ-a, AZ-b의 Private Subnet을 동시에 지정했다.

### 4. IMDSv2 사용 확인

EC2 인스턴스 메타데이터 서비스(IMDS)를 통한 자격증명 탈취는 실제
침해사고(Capital One, 2019)에서 검증된 공격 경로다. IMDSv1은 인증 없는
단순 GET 요청만으로 IAM 임시 자격증명을 반환하지만, IMDSv2는 PUT 요청과
커스텀 헤더(`X-aws-ec2-metadata-token`)를 통한 토큰 발급을 선행해야 한다.
이는 일반적인 SSRF 취약점(URL만 조작 가능한 형태)으로는 우회가 어렵다.
실제 배포된 인스턴스에서 토큰 없는 요청은 `401`로 거부되고, 토큰 기반
요청만 성공하는 것을 확인했다 (아래 검증 로그 참고).

### 5. Private Subnet 인스턴스는 퍼블릭 IP를 갖지 않는다

`map_public_ip_on_launch`를 Private Subnet에 지정하지 않아, 인스턴스가
퍼블릭 IP를 아예 할당받지 않는다. Security Group 설정과 무관하게, 외부에서
접속을 시도할 대상 IP 자체가 존재하지 않으므로 SG 설정 실수에 대한
추가적인 방어선이 된다.

---

## 검증 로그

Terraform으로 배포 후, 실제 AWS Systems Manager Session Manager로
두 인스턴스에 접속해 아래 동작을 직접 확인했다.

### Public EC2

```bash
$ curl -s -m 5 https://checkip.amazonaws.com
100.31.196.104   # 인스턴스의 퍼블릭 IP와 일치 — IGW를 통해 직접 통신

$ curl -s -o /dev/null -w "%{http_code}\n" http://169.254.169.254/latest/meta-data/
401              # 토큰 없는 요청은 거부됨 (IMDSv2 강제 확인)

$ TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
$ curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/iam/security-credentials/
vpc-lab-ssm-role  # 토큰 기반 요청만 성공
```

### Private EC2

```bash
$ curl -s -m 5 https://checkip.amazonaws.com
184.73.238.33    # 인스턴스의 사설 IP(10.0.2.x)가 아닌 NAT Gateway의 퍼블릭 IP

$ aws ec2 describe-instances --instance-ids <private-instance-id> \
    --query "Reservations[0].Instances[0].PublicIpAddress"
null             # 퍼블릭 IP 자체가 존재하지 않음 — 외부 접속 시도가 원천 불가능
```

---

## 트러블슈팅 기록

### AMI 필터 미스로 인한 SSM 접속 실패

**문제**: Session Manager 접속 시도가 계속 `TargetNotConnected`로 실패.

**진단 과정**:
1. `aws ssm describe-instance-information` → 빈 목록. 인스턴스가 SSM에
   전혀 등록되지 않은 상태였다.
2. IAM Instance Profile이 정상적으로 붙어있는지 확인 → 정상.
3. `aws ec2 get-console-output`으로 부팅 로그 확인 → cloud-init은
   정상 완료됐으나 `amazon-ssm-agent` 관련 로그가 단 한 줄도 없었다.
4. 사용된 AMI를 직접 조회 → `al2023-ami-minimal-2023...`. **Minimal
   에디션**이 선택되어 있었다.

**근본 원인**: `most_recent = true`와 느슨한 이름 필터
(`al2023-ami-*-x86_64`)를 사용한 탓에, SSM Agent가 기본 내장되지 않은
AL2023 Minimal 에디션이 "가장 최근"으로 선택되었다.

**해결**:
- AMI 필터를 `al2023-ami-2023.*-kernel-*-x86_64`로 좁혀 Minimal 에디션을
  배제.
- 재발 방지 차원에서 User Data에 SSM Agent 활성화 스크립트를 추가해
  이중 안전망을 구성.

```hcl
locals {
  ssm_user_data = <<-EOF
    #!/bin/bash
    systemctl enable amazon-ssm-agent || dnf install -y amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl restart amazon-ssm-agent
  EOF
}
```

**교훈**: `most_recent`는 "최신"만 보장하지, "의도한 것"을 보장하지
않는다. AMI, 패키지, 컨테이너 이미지 등 자동으로 최신 버전을 가져오는
모든 설정에서 이름 패턴을 명확히 검증하는 습관이 필요하다.

---

## 배포 방법

```bash
git clone <repo-url>
cd secure-vpc-reference
terraform init
terraform plan
terraform apply
```

AWS profile은 `variables.tf`의 `aws_profile` 기본값을 사용하거나
아래와 같이 지정한다.

```bash
terraform apply -var="aws_profile=your-profile"
```

### Session Manager로 접속

```bash
aws ssm start-session --target <instance-id> --profile <profile>
```

로컬에 [Session Manager Plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)이
설치되어 있어야 한다.

---

## 리소스 정리

이 아키텍처는 NAT Gateway 2개, EC2 인스턴스 2대, Interface VPC Endpoint
3개를 포함해 **유료 리소스가 다수 포함**되어 있다. 실습 후 반드시 정리할 것.

```bash
terraform destroy
```

---

## 향후 개선 방향

- [ ] VPC Flow Logs 추가 (트래픽 감사 및 이상 탐지 기반 마련)
- [ ] Interface Endpoint의 Endpoint Policy로 접근 가능한 API 범위 제한
- [ ] GuardDuty / Security Hub 연동
- [ ] Transit Gateway 기반의 보안 검사(Inspection) VPC 분리 구조로 확장
- [ ] Checkov/tfsec을 이용한 Terraform 코드 자체의 정적 보안 검사 추가

---

## 사용 기술

Terraform · AWS VPC · EC2 · NAT Gateway · IAM · Systems Manager ·
VPC Endpoint (PrivateLink)
