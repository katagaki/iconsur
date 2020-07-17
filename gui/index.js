// @ts-nocheck
const React = require('react');
const ReactDOM = require('react-dom');

const Root = () => (
  <div className="app-root">
    <div className="app-title-bar">
      <div className="app-title-bar-icon-close" onClick={() => nw.App.quit()} />
      <div className="app-title">IconSur</div>
    </div>
  </div>
)

ReactDOM.render(<Root />, document.getElementById('app'));