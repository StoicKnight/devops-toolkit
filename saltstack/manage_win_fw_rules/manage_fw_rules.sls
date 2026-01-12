open_port:
  win_firewall.add_rule:
    - name: RULE_NAME (443)
    - localport: 443
    - protocol: tcp
    - action: allow
    - dir: in
    - remoteip: [<LIST_OF_IDS>]
