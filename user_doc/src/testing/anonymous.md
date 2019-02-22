# Anonymous Contracts

Techelson accepts contracts through its `--contract` option. These contracts are named as discussed
in [Creating and Calling Contracts]. Contracts defined at michelson level in testcases and
contracts however are considered *anonymous*. Anonymous contracts can also be deployed and
inspected. In fact, they are not really different from named contracts apart from their lack of
name, which (currently) prevent techelson from mentioning where they really come from in its debug
output.

The following [anonymous.techel] testcase is similar to the one from the [Live Contract Inspection]
except that the contract deployed is not given to the environment, it is inlined in the testcase.

```mic,ignore
{{#include ../../rsc/no_contract/okay/anonymous.techel}}
```

This produces the exact same output (modulo the testcase's name, and as long as we do not increase
verbosity) as for [inspection.techel]:

```
{{#include ../../rsc/no_contract/okay/anonymous.techel.output}}
```

[inspection.techel]: ../../rsc/simpleExample/okay/inspection.techel (The Inspection testcase)
[anonymous.techel]: ../../rsc/no_contract/okay/anonymous.techel (The Anonymous testcase)
[Creating and Calling Contracts]: contracts.md (Creating and calling contracts in techelson)
[Live Contract Inspection]: inspection.md (Live contract inspection in techelson)