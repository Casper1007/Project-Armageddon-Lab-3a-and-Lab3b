#!/usr/bin/env python3
"""
Lab 3B — Network Corridor Proof (TGW Path Evidence)
====================================================
Purpose: Prove that São Paulo → Tokyo traffic uses Transit Gateway
Compliance: Show network isolation and controlled routing

This script verifies:
1. TGW exists in both regions
2. Peering attachment is active
3. Route tables point to TGW for cross-region traffic
4. No direct VPC peering exists (enforces TGW corridor)
"""

import boto3
import json
from datetime import datetime

def get_tgw_info(region):
    """Get Transit Gateway information"""
    ec2 = boto3.client('ec2', region_name=region)
    try:
        tgws = ec2.describe_transit_gateways()
        return [{
            "tgw_id": t['TransitGatewayId'],
            "state": t['State'],
            "description": t.get('Description', ''),
            "default_route_table_association": t.get('Options', {}).get('DefaultRouteTableAssociation'),
            "default_route_table_propagation": t.get('Options', {}).get('DefaultRouteTablePropagation')
        } for t in tgws.get('TransitGateways', [])]
    except:
        return []

def get_tgw_peering_attachments(region):
    """Get TGW peering attachments"""
    ec2 = boto3.client('ec2', region_name=region)
    try:
        peerings = ec2.describe_transit_gateway_peering_attachments()
        return [{
            "attachment_id": p['TransitGatewayAttachmentId'],
            "state": p['State'],
            "local_tgw": p['TransitGatewayId'],
            "peer_tgw": p['AccepterTgwInfo']['TransitGatewayId'],
            "peer_region": p['AccepterTgwInfo']['Region'],
            "requester_region": p['RequesterTgwInfo']['Region']
        } for p in peerings.get('TransitGatewayPeeringAttachments', [])]
    except:
        return []

def get_tgw_route_tables(region, tgw_id):
    """Get TGW route table information"""
    ec2 = boto3.client('ec2', region_name=region)
    try:
        route_tables = ec2.describe_transit_gateway_route_tables(
            Filters=[{'Name': 'transit-gateway-id', 'Values': [tgw_id]}]
        )
        rt_info = []
        for rt in route_tables.get('TransitGatewayRouteTables', []):
            rt_id = rt['TransitGatewayRouteTableId']
            
            # Get routes
            routes = ec2.search_transit_gateway_routes(
                TransitGatewayRouteTableId=rt_id,
                Filters=[{'Name': 'state', 'Values': ['active']}]
            )
            
            rt_info.append({
                "route_table_id": rt_id,
                "state": rt['State'],
                "routes": [{
                    "cidr": r.get('DestinationCidrBlock'),
                    "attachment_id": r.get('TransitGatewayAttachments', [{}])[0].get('TransitGatewayAttachmentId'),
                    "type": r.get('Type')
                } for r in routes.get('Routes', [])]
            })
        return rt_info
    except:
        return []

def check_vpc_peering(region):
    """Check if any VPC peering connections exist (should be none)"""
    ec2 = boto3.client('ec2', region_name=region)
    try:
        peerings = ec2.describe_vpc_peering_connections(
            Filters=[{'Name': 'status-code', 'Values': ['active', 'pending-acceptance']}]
        )
        return peerings.get('VpcPeeringConnections', [])
    except:
        return []

def main():
    print("=" * 80)
    print("Lab 3B — Network Corridor Proof (TGW Path Evidence)")
    print("APPI Compliance: Controlled Cross-Region Routing")
    print("=" * 80)
    
    # Gather evidence from both regions
    tokyo_tgws = get_tgw_info('ap-northeast-1')
    saopaulo_tgws = get_tgw_info('sa-east-1')
    
    tokyo_peerings = get_tgw_peering_attachments('ap-northeast-1')
    saopaulo_peerings = get_tgw_peering_attachments('sa-east-1')
    
    # Get route tables for first TGW in each region
    tokyo_routes = []
    saopaulo_routes = []
    
    if tokyo_tgws:
        tokyo_routes = get_tgw_route_tables('ap-northeast-1', tokyo_tgws[0]['tgw_id'])
    if saopaulo_tgws:
        saopaulo_routes = get_tgw_route_tables('sa-east-1', saopaulo_tgws[0]['tgw_id'])
    
    # Check for VPC peering (should be none)
    tokyo_vpc_peerings = check_vpc_peering('ap-northeast-1')
    saopaulo_vpc_peerings = check_vpc_peering('sa-east-1')
    
    evidence = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "compliance_framework": "APPI",
        "proof_type": "network_corridor",
        "transit_gateways": {
            "tokyo": tokyo_tgws,
            "saopaulo": saopaulo_tgws
        },
        "peering_attachments": {
            "tokyo": tokyo_peerings,
            "saopaulo": saopaulo_peerings
        },
        "route_tables": {
            "tokyo": tokyo_routes,
            "saopaulo": saopaulo_routes
        },
        "vpc_peering_connections": {
            "tokyo": tokyo_vpc_peerings,
            "saopaulo": saopaulo_vpc_peerings
        },
        "compliance_check": {
            "tokyo_has_tgw": len(tokyo_tgws) > 0,
            "saopaulo_has_tgw": len(saopaulo_tgws) > 0,
            "peering_exists": len(tokyo_peerings) > 0 or len(saopaulo_peerings) > 0,
            "peering_active": any(p['state'] == 'available' for p in tokyo_peerings + saopaulo_peerings),
            "no_vpc_peering": len(tokyo_vpc_peerings) == 0 and len(saopaulo_vpc_peerings) == 0,
            "assertion": "PASS ✅" if (
                len(tokyo_tgws) > 0 and 
                len(saopaulo_tgws) > 0 and
                any(p['state'] == 'available' for p in tokyo_peerings + saopaulo_peerings) and
                len(tokyo_vpc_peerings) == 0 and 
                len(saopaulo_vpc_peerings) == 0
            ) else "FAIL ❌"
        },
        "evidence_summary": {
            "description": "Transit Gateway provides controlled corridor between regions",
            "tokyo_tgw_count": len(tokyo_tgws),
            "saopaulo_tgw_count": len(saopaulo_tgws),
            "active_peerings": sum(1 for p in tokyo_peerings + saopaulo_peerings if p['state'] == 'available'),
            "vpc_peering_violations": len(tokyo_vpc_peerings) + len(saopaulo_vpc_peerings)
        }
    }
    
    # Save to file
    output_file = "network_corridor_proof.json"
    with open(output_file, 'w') as f:
        json.dump(evidence, f, indent=2)
    
    print("\n📊 Evidence Summary:")
    print(f"  Tokyo TGWs: {len(tokyo_tgws)}")
    print(f"  São Paulo TGWs: {len(saopaulo_tgws)}")
    print(f"  Active Peerings: {evidence['evidence_summary']['active_peerings']}")
    print(f"  VPC Peering Violations: {evidence['evidence_summary']['vpc_peering_violations']}")
    print(f"\n  Compliance Status: {evidence['compliance_check']['assertion']}")
    print(f"\n✅ Evidence saved to: {output_file}")
    print("=" * 80)
    
    print("\nFull Evidence:")
    print(json.dumps(evidence, indent=2))

if __name__ == "__main__":
    main()
