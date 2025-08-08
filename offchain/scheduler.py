#!/usr/bin/env python3
import os
import time
import random
from web3 import Web3
from eth_account import Account
from eth_account.signers.local import LocalAccount
from typing import Optional

RPC_URL = os.getenv("RPC_URL", "http://localhost:8545")
PRIVATE_KEY = os.getenv("PRIVATE_KEY", "")
JOB_MANAGER = Web3.to_checksum_address(os.getenv("JOB_MANAGER", "0x0000000000000000000000000000000000000000"))
COMPUTE_ESCROW = Web3.to_checksum_address(os.getenv("COMPUTE_ESCROW", "0x0000000000000000000000000000000000000000"))
START_BLOCK = int(os.getenv("START_BLOCK", "0"))
AUDIT_PROBABILITY = float(os.getenv("AUDIT_PROBABILITY", "0.2"))
POLL_INTERVAL = int(os.getenv("POLL_INTERVAL", "10"))

w3 = Web3(Web3.HTTPProvider(RPC_URL))
assert w3.is_connected(), "Cannot connect to RPC"

acct: Optional[LocalAccount] = None
if PRIVATE_KEY:
    acct = Account.from_key(PRIVATE_KEY)

job_manager_abi = [
    {"anonymous":False,"inputs":[{"indexed":True,"internalType":"uint256","name":"jobId","type":"uint256"},{"indexed":True,"internalType":"address","name":"client","type":"address"},{"indexed":False,"internalType":"uint8","name":"jobType","type":"uint8"},{"indexed":False,"internalType":"uint256","name":"payment","type":"uint256"},{"indexed":False,"internalType":"bool","name":"preferGreen","type":"bool"}],"name":"JobCreated","type":"event"},
    {"inputs":[{"internalType":"uint256","name":"jobId","type":"uint256"}],"name":"assignJobToOptimalNode","outputs":[],"stateMutability":"nonpayable","type":"function"},
    {"inputs":[{"internalType":"uint256","name":"jobId","type":"uint256"},{"internalType":"bool","name":"enabled","type":"bool"}],"name":"setJobAudit","outputs":[],"stateMutability":"nonpayable","type":"function"},
]

escrow_abi = [
    {"inputs":[{"internalType":"uint256","name":"jobId","type":"uint256"}],"name":"isFunded","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"}
]

job_manager = w3.eth.contract(address=JOB_MANAGER, abi=job_manager_abi)
escrow = w3.eth.contract(address=COMPUTE_ESCROW, abi=escrow_abi) if COMPUTE_ESCROW != Web3.to_checksum_address("0x0") else None


def send_tx(fn):
    assert acct is not None, "PRIVATE_KEY required"
    tx = fn.build_transaction({
        'from': acct.address,
        'nonce': w3.eth.get_transaction_count(acct.address),
        'gas': 1_000_000,
        'maxFeePerGas': w3.to_wei('2', 'gwei'),
        'maxPriorityFeePerGas': w3.to_wei('1', 'gwei'),
        'chainId': w3.eth.chain_id,
    })
    signed = acct.sign_transaction(tx)
    tx_hash = w3.eth.send_raw_transaction(signed.rawTransaction)
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
    if receipt.status != 1:
        raise RuntimeError('Transaction failed')
    return receipt


def process_job(job_id: int):
    # Randomly enable audit for a subset of jobs before assignment
    if random.random() < AUDIT_PROBABILITY:
        try:
            send_tx(job_manager.functions.setJobAudit(job_id, True))
            print(f"Enabled audit for job {job_id}")
        except Exception as e:
            print(f"Audit enable failed for job {job_id}: {e}")

    # If escrow present, ensure funded before assignment
    if escrow is not None:
        try:
            funded = escrow.functions.isFunded(job_id).call()
            if not funded:
                print(f"Job {job_id} not funded yet; skipping assignment")
                return
        except Exception as e:
            print(f"Escrow check failed for job {job_id}: {e}")

    # Assign job to optimal node
    try:
        send_tx(job_manager.functions.assignJobToOptimalNode(job_id))
        print(f"Assigned job {job_id}")
    except Exception as e:
        print(f"Assignment failed for job {job_id}: {e}")


def main():
    print("Scheduler started", {
        'chainId': w3.eth.chain_id,
        'jobManager': JOB_MANAGER,
        'escrow': COMPUTE_ESCROW,
        'from': acct.address if acct else None,
    })
    last_block = START_BLOCK or w3.eth.block_number
    while True:
        try:
            current = w3.eth.block_number
            if current >= last_block:
                # Scan recent JobCreated events
                ev = job_manager.events.JobCreated().create_filter(fromBlock=last_block, toBlock=current)
                for e in ev.get_all_entries():
                    job_id = int(e['args']['jobId'])
                    print(f"Discovered job {job_id} from {e['args']['client']}")
                    process_job(job_id)
                last_block = current + 1
        except Exception as e:
            print(f"Loop error: {e}")
        time.sleep(POLL_INTERVAL)


if __name__ == '__main__':
    main()
