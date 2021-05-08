#!/usr/bin/env bash
# run.sh: run the model against a clean testnet, and clean up afterwards

set -e

# Have a function to kill off Ganache and clean up the database when we quit.
function cleanup {
    echo "Clean Up..."
    rm *-approvals.json
}

trap cleanup EXIT

echo "Deploying contracts..."
time truffle migrate --reset -f 2 --to 2 --skip-dry-run --network=development | tee deploy_output.txt
#curl -X POST --data @q.txt -H "Content-Type: application/json" http://127.0.0.1:9545/ext/bc/evm/rpc | python -m json.tool


#'
if [[ ! -e venv ]] ; then
    # Set up the virtual environment
    echo "Preparing Virtual Environment..."
    virtualenv --python python3 venv
    . venv/bin/activate
    pip3 install -r requirements.txt
    time python -m py_compile model.py
else
    # Just go into it
    echo "Entering Virtual Environment..."
    . venv/bin/activate
    time python -m py_compile model.py
fi

if [[ "${RUN_SHELL}" == "1" ]] ; then
    # Run a shell so that you can run the model several times
    echo "Running Interactive Shell..."
    bash
else
    # Run the model
    echo "Running Model..."
    ./model.py
fi

# grep -P "^  Gas usage: .{6,}" ganache_output.txt | wc -l
# grep -P "^  Gas usage: .{0,}" ganache_output.txt | wc -l


