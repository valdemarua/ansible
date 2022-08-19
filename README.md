## Usage

Install ansible, vagrant, virtualbox

### How to test

1. Uncomment these lines in ansible.cnf:
```
private_key_file = ~/.vagrant.d/insecure_private_key
host_key_checking = False
```

2. Run vagrant:
```
vagrant up
```

3. Run playbook:

```
ansible-playbook test-initial-setup.yml
```
