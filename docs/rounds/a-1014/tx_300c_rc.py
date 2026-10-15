# test_300c ends on "grep && { error }", whose status is 1 when the check
# passes; as the last statement that made run_one() fail the test.
P = 'lustre/tests/conf-sanity.sh'
O = """	grep -q -- "-OST" $scan_err && {
		cat $scan_err
		error "lfs find --local --mdt $mdtsvc read an OST"
	}
}
run_test 300c """
N = """	if grep -q -- "-OST" $scan_err; then
		cat $scan_err
		error "lfs find --local --mdt $mdtsvc read an OST"
	fi
}
run_test 300c """
def fn(path, s, subj):
    return s.replace(O, N) if path == P else s
