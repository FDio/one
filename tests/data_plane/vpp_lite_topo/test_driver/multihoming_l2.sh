source config.sh
source odl_utils.sh
source topologies/multihoming_topo_l2.sh

ODL_CONFIG_FILE1="vpp1.json"
ODL_CONFIG_FILE2="vpp2.json"
ODL_CONFIG_FILE3="update_vpp2.json"

if [ "$1" == "clean" ] ; then
  multihoming_topo_clean
  exit 0
fi

if [[ $(id -u) != 0 ]]; then
  echo "Error: run this as a root."
  exit 1
fi

function test_multihoming
{
  if [ "$3" != "no_setup" ] ; then
    multihoming_topo_setup
  fi

  maybe_pause $3

  test_result=1

  ip netns exec vppns1 "${1}" -w 15 -c 1 "${2}"
  rc=$?
  if [ $rc -ne 0 ] ; then
    echo "No response received!"

    maybe_pause $3
    multihoming_topo_clean
    exit $test_result
  fi

  maybe_pause $3

  # do some port sweeping to see that load balancing works
  ip netns exec vppns1 python scripts/port_flood.py "${2}" 1000

  # check that it works
  pkts=$(echo "show int" | nc 0 5003 | grep host-intervpp12 | awk '{print $6}' | tr -d '\r')

  if [ $pkts -gt 450 ] && [ $pkts -lt 550 ] ; then
    rc=0
  else
    rc=1
  fi

  if [ $rc -ne 0 ] ; then
    echo "Load balancing doesn't work!"

    maybe_pause $3

    multihoming_topo_clean
    exit $test_result
  fi

  maybe_pause $3

  # change IP addresses of destination RLOC
  echo "set int ip address del host-intervpp12 6.0.3.2/24" | nc 0 5003
  echo "set int ip address host-intervpp12 6.0.3.20/24" | nc 0 5003
  echo "set int ip address del host-intervpp12 6:0:3::2/64" | nc 0 5003
  echo "set int ip address host-intervpp12 6:0:3::20/64" | nc 0 5003
  post_curl "update-mapping" ${ODL_CONFIG_FILE3}

  ip netns exec vppns1 "${1}" -w 15 -c 1 "${2}"
  rc=$?

  # test done

  maybe_pause $3

  multihoming_topo_clean
  print_status $rc "No ICMP response!"
  exit $test_result
}
