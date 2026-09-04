set worklib [file join $::env(WORKDIR) work]
vlib $worklib
vmap work $worklib
vlog -sv -suppress 2892 -f fvip_validation/qverify/manager_offer_mutation.f
formal compile -d tb_manager_offer_mutation -G MUTATION=$::env(MUTATION)
formal verify -auto_constraint_off -jobs 4 -timeout 1m
vmap work [file join [pwd] work]
exit
