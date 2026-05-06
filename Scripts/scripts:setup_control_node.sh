
#!/bin/bash
# setup_control_node.sh — run once on the ansible control node EC2

echo "=== Installing dependencies ==="
sudo yum install -y python3-pip git

echo "=== Installing Ansible ==="
pip3 install --user ansible boto3 botocore

echo "=== Installing AWS collections ==="
ansible-galaxy collection install amazon.aws community.aws --force

echo "=== Verifying ==="
ansible --version
python3 -c "import boto3; print(f'boto3 {boto3.__version__}')"
aws --version

echo ""
echo "=== Done. Next steps: ==="
echo "1. Configure ~/.aws/config with spoke profiles"
echo "2. Run: ansible-inventory --graph"
echo "3. Run: ansible-playbook playbooks/deploy_monitoring.yml"

