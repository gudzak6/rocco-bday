"use client";

import "maplibre-gl/dist/maplibre-gl.css";
import { useEffect, useRef, useState } from "react";
import type { Map as MapLibreMap, Marker } from "maplibre-gl";

export function MapPinPicker() {
  const container = useRef<HTMLDivElement>(null);
  const map = useRef<MapLibreMap | null>(null);
  const marker = useRef<Marker | null>(null);
  const [latitude, setLatitude] = useState(40.7128);
  const [longitude, setLongitude] = useState(-74.006);
  const [query, setQuery] = useState("");

  useEffect(() => {
    if (!container.current || map.current) return;
    let cancelled = false;
    void import("maplibre-gl").then(({ default: maplibregl }) => {
      if (cancelled || !container.current) return;
      const instance = new maplibregl.Map({
        container: container.current,
        style: "https://tiles.openfreemap.org/styles/liberty",
        center: [-74.006, 40.7128],
        zoom: 11,
      });
      const pin = new maplibregl.Marker({ color: "#7555E8", draggable: true })
        .setLngLat([-74.006, 40.7128]).addTo(instance);
      const update = () => {
        const point = pin.getLngLat();
        setLatitude(Number(point.lat.toFixed(6)));
        setLongitude(Number(point.lng.toFixed(6)));
      };
      pin.on("dragend", update);
      instance.on("click", (event) => { pin.setLngLat(event.lngLat); update(); });
      map.current = instance;
      marker.current = pin;
    });
    return () => {
      cancelled = true;
      map.current?.remove();
      map.current = null;
    };
  }, []);

  async function search() {
    const response = await fetch(`/api/geocode?q=${encodeURIComponent(query)}`);
    const result = await response.json() as { latitude?: number; longitude?: number };
    if (result.latitude == null || result.longitude == null) return;
    setLatitude(result.latitude); setLongitude(result.longitude);
    marker.current?.setLngLat([result.longitude, result.latitude]);
    map.current?.flyTo({ center: [result.longitude, result.latitude], zoom: 15 });
  }

  return (
    <div className="space-y-3">
      <div className="flex gap-2">
        <label className="sr-only" htmlFor="address-search">Search address</label>
        <input id="address-search" className="field" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search an address" />
        <button type="button" className="button secondary" onClick={search}>Find</button>
      </div>
      <div ref={container} className="h-64 overflow-hidden rounded-xl" aria-label="Map pin picker" />
      <div className="grid grid-cols-2 gap-3">
        <label>Latitude<input className="field mt-1" name="latitude" type="number" step="any" value={latitude} onChange={(e) => setLatitude(e.target.valueAsNumber)} required /></label>
        <label>Longitude<input className="field mt-1" name="longitude" type="number" step="any" value={longitude} onChange={(e) => setLongitude(e.target.valueAsNumber)} required /></label>
      </div>
    </div>
  );
}
