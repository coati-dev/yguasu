defmodule Jagua.Sentinels.HeatmapTest do
  use Jagua.DataCase, async: true

  import Jagua.Factory

  alias Jagua.Sentinels.Heatmap

  describe "build/1" do
    test "returns the correct structure" do
      sentinel = create_sentinel(interval: :hourly)
      result = Heatmap.build(sentinel)

      assert %{cells: cells, interval: :hourly, count: count} = result
      assert is_list(cells)
      assert count == 168
      assert length(cells) == count
    end

    test "each cell has required fields" do
      sentinel = create_sentinel(interval: :hourly)
      %{cells: cells} = Heatmap.build(sentinel)

      for cell <- cells do
        assert Map.has_key?(cell, :bucket_start)
        assert Map.has_key?(cell, :bucket_end)
        assert Map.has_key?(cell, :status)
        assert Map.has_key?(cell, :count)
        assert cell.status in [:healthy, :errored, :missed, :unknown, :future]
      end
    end

    test "cells before sentinel creation are :unknown" do
      # Create sentinel now and check that cells before now are :unknown
      sentinel = create_sentinel(interval: :hourly)
      %{cells: cells} = Heatmap.build(sentinel)

      unknown_cells = Enum.filter(cells, &(&1.status == :unknown))
      # All unknown cells should have bucket_start before sentinel.inserted_at
      for cell <- unknown_cells do
        assert DateTime.compare(cell.bucket_start, sentinel.inserted_at) == :lt
      end
    end

    test "future cells have :future status" do
      sentinel = create_sentinel(interval: :hourly)
      %{cells: cells} = Heatmap.build(sentinel)

      future_cells = Enum.filter(cells, &(&1.status == :future))
      now = DateTime.utc_now()

      for cell <- future_cells do
        assert DateTime.compare(cell.bucket_start, now) == :gt
      end
    end

    test "cells are ordered oldest first" do
      sentinel = create_sentinel(interval: :daily)
      %{cells: cells} = Heatmap.build(sentinel)

      pairs = Enum.zip(cells, tl(cells))

      for {a, b} <- pairs do
        assert DateTime.compare(a.bucket_start, b.bucket_start) in [:lt, :eq]
      end
    end
  end

  describe "bucket_for/2" do
    test "sub-day intervals align to epoch multiples" do
      dt = ~U[2026-01-15 14:37:00Z]
      # hourly: should snap to 14:00
      bucket = Heatmap.bucket_for(dt, :hourly)
      assert bucket == ~U[2026-01-15 14:00:00Z]
    end

    test "daily aligns to midnight UTC" do
      dt = ~U[2026-01-15 14:37:00Z]
      bucket = Heatmap.bucket_for(dt, :daily)
      assert bucket == ~U[2026-01-15 00:00:00Z]
    end

    test "weekly aligns to Monday midnight UTC" do
      # 2026-01-15 is a Thursday
      dt = ~U[2026-01-15 14:37:00Z]
      bucket = Heatmap.bucket_for(dt, :weekly)
      # Previous Monday was 2026-01-12
      assert bucket == ~U[2026-01-12 00:00:00Z]
    end

    test "monthly aligns to first of month" do
      dt = ~U[2026-01-15 14:37:00Z]
      bucket = Heatmap.bucket_for(dt, :monthly)
      assert bucket == ~U[2026-01-01 00:00:00Z]
    end
  end
end
