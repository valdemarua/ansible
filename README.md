## Roles
* packages (installs essentials packages)
* certbot (installs snpad package, installs core, certbot snaps)
* fail2ban (installs, enable fail2ban)
* ufw (installs, enables ufw and allows 22, 80, 443 ports)

## Usage

Install ansible, vagrant, virtualbox

### How to use

Copy `hosts.sample` to `hosts`. Update hosts list inside `hosts` file.

Run playbook on all hosts:
```
ansible-playbook initial-setup.yml
```

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
