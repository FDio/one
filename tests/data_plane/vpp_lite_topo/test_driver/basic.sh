source config.sh
source odl_utils.sh
source topologies/2_node_topo.sh

ODL_CONFIG_FILE1="vpp1.json"
ODL_CONFIG_FILE2="vpp2.json"
ODL_CONFIG_FILE3="update_vpp2.json"

if [ "$1" == "clean" ] ; then
  2_node_topo_clean
  exit 0
fi

if [[ $(id -u) != 0 ]]; then
  echo "Error: run this as a root."
  exit 1
fi

function test_basic
{
  if [ "$3" != "no_setup" ] ; then
    2_node_topo_setup
  fi

  maybe_pause
  test_result=1

  ip netns exec vppns1 "${1}" -w 15 -c 1 "${2}"
  assert_rc_ok $? 2_node_topo_clean "No ICMP response!"

  maybe_pause
  # change IP addresses of destination RLOC
  echo "set int ip address del host-intervpp2 6.0.3.2/24" | nc 0 5003
  echo "set int ip address host-intervpp2 6.0.3.20/24" | nc 0 5003
  echo "set int ip address del host-intervpp2 6:0:3::2/64" | nc 0 5003
  echo "set int ip address host-intervpp2 6:0:3::20/64" | nc 0 5003
  post_curl "update-mapping" ${ODL_CONFIG_FILE3}

  ip netns exec vppns1 "${1}" -w 15 -c 1 "${2}"
  rc=$?

  # test done

  maybe_pause
  2_node_topo_clean
  print_status $rc "No ICMP response!"
  exit $test_result
}

function test_basic_map_register_fallback
{
  2_node_topo_setup no_odl

  maybe_pause

  test_result=1

  start_map_server "6.0.3.200"

  wait_for_map_register=20
  echo "Waiting for map registration $wait_for_map_register seconds .."
  sleep $wait_for_map_register

  rc=1

  count="`echo "show error" | nc 0 5002 | grep 'map-notifies received' | awk '{print $1}'`"
  if [ "$count" != "" ] ; then
    if [ $count -gt 0 ] ; then
      echo "no map-notifies received! ($count)"
      rc=0 # test passed
    fi
  fi

  maybe_pause
  kill $ms_id

  # test done
  2_node_topo_clean no_odl
  print_status $rc "map server fallback does not work!"
  exit $test_result
}

function test_basic_map_register
{
  2_node_topo_setup no_odl
  post_curl "add-key" ${ODL_CONFIG_FILE1}
  post_curl "add-key" ${ODL_CONFIG_FILE2}

  maybe_pause

  test_result=1

  wait_for_map_register=10
  echo "Waiting for map registration $wait_for_map_register seconds .."
  sleep $wait_for_map_register

  ip netns exec vppns1 "${1}" -w 15 -c 1 "${2}"
  rc=$?

  count=`echo "show error" | nc 0 5002 | grep 'map-notifies received' | awk '{print $1}'`
  if [ "$count" -eq 0 ] ; then
    echo "no map-notifies received! ($count)"
    rc=1
  fi

  maybe_pause

  # test done
  2_node_topo_clean
  print_status $rc "No ICMP response!"
  exit $test_result
}

function test_rloc_probe
{
  2_node_topo_setup

  maybe_pause
  test_result=1

  ip netns exec vppns1 "${1}" -w 15 -c 1 "${2}"
  rc=$?
  assert_rc_ok $rc 2_node_topo_clean "No ICMP response!"

  sleep 65

  count=`echo "show error" | nc 0 5002 | grep 'rloc-probe replies received' | awk '{print $1}'`
  if [ "$count" != "1" ] ; then
    echo "rloc-probe replies received is not 1! ($count)"
    rc=1
  fi

  count=`echo "show error" | nc 0 5003 | grep 'rloc-probe requests received' | awk '{print $1}'`
  if [ "$count" != "1" ] ; then
    echo "rloc-probe requests received is not 1! ($count)"
    rc=1
  fi

  # test done

  maybe_pause
  2_node_topo_clean
  print_status $rc "unexpected value"
  exit $test_result
}

function test_enable_disable
{
  if [ "$3" != "no_setup" ] ; then
    2_node_topo_setup
  fi

  maybe_pause
  test_result=1

  ip netns exec vppns1 "${1}" -w 15 -c 1 "${2}"
  assert_rc_ok $? 2_node_topo_clean "No ICMP response!"

  maybe_pause

  # disable control plane
  echo "one disable" | nc 0 5002
  ip netns exec vppns1 "${1}" -w 15 -c 1 "${2}"
  assert_rc_not_ok $? 2_node_topo_clean "Nothing expected, but received ICMP reply!"

  # enable control plane
  echo "one enable" | nc 0 5002
  ip netns exec vppns1 "${1}" -w 15 -c 1 "${2}"
  assert_rc_ok $? 2_node_topo_clean "No ICMP response!"

  # disable dataplane
  echo "gpe disable" | nc 0 5002
  ip netns exec vppns1 "${1}" -w 15 -c 1 "${2}"
  assert_rc_not_ok $? 2_node_topo_clean "Nothing expected, but received ICMP reply!"

  # enable LISP again from control plane
  echo "one enable" | nc 0 5002
  ip netns exec vppns1 "${1}" -w 15 -c 1 "${2}"
  assert_rc_ok $? 2_node_topo_clean "No ICMP response!"
  rc=$?

  # test done
  maybe_pause
  2_node_topo_clean
  print_status $rc "No ICMP response!"
  exit $test_result
}
