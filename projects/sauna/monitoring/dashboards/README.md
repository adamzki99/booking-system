# Sauna project dashboards

Place sauna-specific Grafana dashboard JSON files in this directory. They are
provisioned by the sauna monitoring instance into a Grafana folder named after
`MONITORING_PROJECT` (default: `sauna`).

Generic product dashboards live in `product/monitoring/grafana/dashboards/` and
are provisioned into the `Product` folder for every project instance. Keep
sauna-only operational views here; do not add sauna-specific dashboards to the
generic product.

## How to add a dashboard

1. Create a dashboard in Grafana, or write a dashboard JSON file.
2. Set a stable `uid`, a clear `title`, and tags.
3. Save the JSON file in this directory (for example `sauna-capacity.json`).
4. Restart or wait for Grafana provisioning refresh (30s).
5. Run `product/monitoring/scripts/validate.sh` and check the dashboard loads.

No sauna-specific dashboard is included yet because the generic product metrics
do not currently expose sauna-only capacity/utilisation data. Add one here when
sauna-specific metrics or views are available.
