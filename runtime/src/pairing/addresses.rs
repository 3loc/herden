use std::collections::HashSet;
use std::io;
use std::net::IpAddr;

pub(crate) fn candidates() -> io::Result<Vec<String>> {
    let mut seen = HashSet::new();
    let mut addresses = if_addrs::get_if_addrs()?
        .into_iter()
        .filter_map(|interface| {
            let address = interface.ip();
            is_routable(address).then_some(address)
        })
        .filter(|address| seen.insert(*address))
        .collect::<Vec<_>>();
    addresses.sort_by_key(|address| rank(*address));

    let likely = addresses
        .iter()
        .copied()
        .filter(|address| is_likely(*address))
        .map(|address| address.to_string())
        .collect::<Vec<_>>();
    if likely.is_empty() {
        Ok(addresses
            .into_iter()
            .map(|address| address.to_string())
            .collect())
    } else {
        Ok(likely)
    }
}

fn is_routable(address: IpAddr) -> bool {
    match address {
        IpAddr::V4(address) => !address.is_loopback() && !address.is_link_local(),
        IpAddr::V6(address) => !address.is_loopback() && !address.is_unicast_link_local(),
    }
}

fn is_likely(address: IpAddr) -> bool {
    match address {
        IpAddr::V4(address) => {
            let octets = address.octets();
            address.is_private() || (octets[0] == 100 && (64..=127).contains(&octets[1]))
        }
        IpAddr::V6(address) => address.octets()[0] & 0xfe == 0xfc,
    }
}

fn rank(address: IpAddr) -> (u8, u8, String) {
    (
        u8::from(!is_likely(address)),
        u8::from(address.is_ipv6()),
        address.to_string(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn likely_addresses_include_lan_and_tailnet_ranges() {
        for address in ["10.1.2.3", "172.20.1.2", "192.168.1.4", "100.100.2.3"] {
            assert!(is_likely(address.parse().expect("IP address")), "{address}");
        }
        assert!(!is_likely("8.8.8.8".parse().expect("IP address")));
    }

    #[test]
    fn link_local_and_loopback_addresses_are_not_routable() {
        for address in ["127.0.0.1", "169.254.1.2", "::1", "fe80::1"] {
            assert!(
                !is_routable(address.parse().expect("IP address")),
                "{address}"
            );
        }
    }
}
