import './statistics-charts.css';

export function AttendanceDonutChart({ title, data }) {
  const total = data.reduce((sum, item) => sum + Math.max(0, Number(item.value) || 0), 0);
  if (!total) return null;

  let cursor = 0;
  const segments = data.filter((item) => Number(item.value) > 0).map((item) => {
    const start = cursor;
    cursor += Number(item.value) / total * 100;
    return `${item.color} ${start}% ${cursor}%`;
  });

  return (
    <section className="statistics-chart">
      <h2>{title}</h2>
      <div className="statistics-donut-layout">
        <div className="statistics-donut" role="img" aria-label={`${title}: ${total} kết quả`} style={{ background: `conic-gradient(from -90deg, ${segments.join(', ')})` }}>
          <div className="statistics-donut-center"><strong>{total}</strong><span>kết quả</span></div>
        </div>
        <div className="statistics-legend">
          {data.map((item) => {
            const value = Math.max(0, Number(item.value) || 0);
            return <div className="statistics-legend-row" key={item.label}><i style={{ backgroundColor: item.color }} /><span>{item.label}</span><strong>{value}</strong><small>{Math.round(value * 100 / total)}%</small></div>;
          })}
        </div>
      </div>
    </section>
  );
}

export function AttendanceBarChart({ title, categories, series }) {
  if (!categories.length || !series.length) return null;
  const maxValue = Math.max(1, ...series.flatMap((item) => item.values.map((value) => Number(value) || 0)));
  const ticks = [1, 0.75, 0.5, 0.25, 0];
  const minWidth = Math.max(100, categories.length * 64);

  return (
    <section className="statistics-chart">
      <h2>{title}</h2>
      <div className="statistics-legend statistics-series-legend">
        {series.map((item) => <div className="statistics-series-item" key={item.label}><i style={{ backgroundColor: item.color }} />{item.label}</div>)}
      </div>
      <div className="statistics-chart-scroll">
        <div className="statistics-chart-inner" style={{ minWidth }}>
          <div className="statistics-plot-row">
            <div className="statistics-axis-labels">{ticks.map((tick) => <span key={tick}>{Math.round(maxValue * tick)}</span>)}</div>
            <div className="statistics-plot-area">
              <div className="statistics-gridlines">{ticks.map((tick) => <i key={tick} />)}</div>
              <div className="statistics-bar-groups" style={{ '--category-count': categories.length }}>
                {categories.map((category, index) => <div className="statistics-bar-group" key={`${category}-${index}`}>
                  {series.map((item) => {
                    const value = Number(item.values[index]) || 0;
                    const color = item.pointColors?.[index] || item.color;
                    return <span className="statistics-bar-slot" key={item.label} title={`${item.label}: ${value}`}><i className="statistics-bar" style={{ height: `${value ? Math.max(2, value / maxValue * 100) : 0}%`, backgroundColor: color }} /></span>;
                  })}
                </div>)}
              </div>
            </div>
          </div>
          <div className="statistics-x-labels" style={{ '--category-count': categories.length }}><span />{categories.map((category, index) => <small key={`${category}-${index}`} title={category}>{category}</small>)}</div>
        </div>
      </div>
    </section>
  );
}