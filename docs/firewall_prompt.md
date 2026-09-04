The goal is to build a formally verified axi firewall module that protects an soc from vulnerabilities in docs/{expect,xray}.pdf and more (do a deep research). This will be an IP, someone can drop along any AXI bus to get the security, stability and isolation benefits with minimal performance/area impact.

The IP should have N AXI subordinates and managers, where S[i] is connected to M[i]. Firstly, we will take care of basic security stuff like all data fields = 0 if valid =0.

Then, for the attacks/protocol violations that cannot be blocked (eg: wlast doesnt come after the number of beats specified in aw), the IP should record this violation happened in this port, and raise an exception to the CPU. The CPU can then check it, and ask the IP to reset the modules if needed.

This IP should be formally verified. RTL and formal files should live inside ./firewall

First, do some deep research, come up with an architecture. it should be simple and as few lines as possible. we will use PULP's axi interfaces, cmds...etc to keep codebase small. Also suggest new features we can add.